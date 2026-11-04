// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// The pipeline part of the Swift bridge, after upstream's
// Firestore/Source/API/FIRPipelineBridge.mm (13.1.1).

#include "Firestore/include/PipelineBridge.h"

#include <memory>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "Firestore/core/src/api/aggregate_expressions.h"
#include "Firestore/core/src/api/document_reference.h"
#include "Firestore/core/src/api/expressions.h"
#include "Firestore/core/src/api/firestore.h"
#include "Firestore/core/src/api/firestore_bridge_internal.h"
#include "Firestore/core/src/api/ordering.h"
#include "Firestore/core/src/api/pipeline.h"
#include "Firestore/core/src/api/pipeline_result.h"
#include "Firestore/core/src/api/pipeline_result_change.h"
#include "Firestore/core/src/api/pipeline_snapshot.h"
#include "Firestore/core/src/api/query_core.h"
#include "Firestore/core/src/api/query_listener_registration.h"
#include "Firestore/core/src/api/realtime_pipeline.h"
#include "Firestore/core/src/api/realtime_pipeline_snapshot.h"
#include "Firestore/core/src/api/snapshot_metadata.h"
#include "Firestore/core/src/api/stages.h"
#include "Firestore/core/src/api/write_batch.h"
#include "Firestore/core/src/core/event_listener.h"
#include "Firestore/core/src/core/firestore_client.h"
#include "Firestore/core/src/core/listen_options.h"
#include "Firestore/core/src/core/pipeline_util.h"
#include "Firestore/core/src/core/view_snapshot.h"
#include "Firestore/core/src/model/database_id.h"
#include "Firestore/core/src/model/document_key.h"
#include "Firestore/core/src/model/field_path.h"
#include "Firestore/core/src/model/object_value.h"
#include "Firestore/core/src/model/snapshot_version.h"
#include "Firestore/core/src/nanopb/message.h"
#include "Firestore/core/src/nanopb/nanopb_util.h"
#include "Firestore/core/src/remote/serializer.h"
#include "Firestore/core/src/util/exception.h"
#include "Firestore/core/src/util/hard_assert.h"
#include "Firestore/core/src/util/status.h"
#include "Firestore/core/src/util/statusor.h"

#include "absl/types/optional.h"

namespace firebase {
namespace firestore {
namespace swift_bridge {

using api::Expr;
using api::Firestore;
using api::Ordering;
using api::Stage;
using model::FieldPath;
using util::Status;
using util::StatusOr;
using util::ThrowInvalidArgument;

using ExprMap = std::unordered_map<std::string, std::shared_ptr<Expr>>;

/// Reaches the API objects behind the pipeline bridge types.
struct PipelineAccess {
  static const std::shared_ptr<Expr>& Get(const ExprBridge& expr) {
    return expr.expr_;
  }
  static const std::shared_ptr<api::AggregateFunction>& Get(
      const AggregateFunctionBridge& function) {
    return function.function_;
  }
  static const Ordering& Get(const OrderingBridge& ordering) {
    return *ordering.ordering_;
  }
  static const std::shared_ptr<Stage>& Get(const StageBridge& stage) {
    return stage.stage_;
  }
  static const std::shared_ptr<api::Pipeline>& Get(
      const PipelineBridge& pipeline) {
    return pipeline.pipeline_;
  }
  static const std::shared_ptr<RawStageParamBridge::Impl>& Get(
      const RawStageParamBridge& param) {
    return param.impl_;
  }

  static ExprBridge MakeExpr(std::shared_ptr<Expr> expr) {
    ExprBridge result;
    result.expr_ = std::move(expr);
    return result;
  }
  static StageBridge MakeStage(std::shared_ptr<Stage> stage) {
    StageBridge result;
    result.stage_ = std::move(stage);
    return result;
  }
  static PipelineResultBridge MakeResult(api::PipelineResult result,
                                         std::shared_ptr<Firestore> firestore);
  static PipelineResultChangeBridge MakeChange(
      api::PipelineResultChange change, std::shared_ptr<Firestore> firestore) {
    PipelineResultChangeBridge bridge;
    bridge.change_ =
        std::make_shared<api::PipelineResultChange>(std::move(change));
    bridge.firestore_ = std::move(firestore);
    return bridge;
  }
  static PipelineSnapshotBridge* NewSnapshot(api::PipelineSnapshot snapshot) {
    auto* bridge = new PipelineSnapshotBridge();
    bridge->snapshot_ =
        std::make_shared<api::PipelineSnapshot>(std::move(snapshot));
    return bridge;
  }
  static RealtimePipelineSnapshotBridge* NewSnapshot(
      api::RealtimePipelineSnapshot snapshot) {
    auto* bridge = new RealtimePipelineSnapshotBridge();
    bridge->snapshot_ =
        std::make_shared<api::RealtimePipelineSnapshot>(std::move(snapshot));
    return bridge;
  }
  static PipelineBridge MakePipeline(std::shared_ptr<api::Pipeline> pipeline) {
    PipelineBridge result;
    result.pipeline_ = std::move(pipeline);
    return result;
  }
};

namespace {

std::string EnsureLeadingSlash(const std::string& path) {
  if (!path.empty() && path[0] == '/') {
    return path;
  }
  return "/" + path;
}

absl::optional<std::string> OptionalString(const std::string& value) {
  if (value.empty()) return absl::nullopt;
  return value;
}

ExprMap MakeExprMap(const NamedExprBridges& exprs) {
  ExprMap result;
  for (const auto& entry : exprs) {
    result[entry.first] = PipelineAccess::Get(entry.second);
  }
  return result;
}

std::vector<std::shared_ptr<Expr>> MakeExprs(const ExprBridgeVector& exprs) {
  std::vector<std::shared_ptr<Expr>> result;
  result.reserve(exprs.size());
  for (const auto& expr : exprs) {
    result.push_back(PipelineAccess::Get(expr));
  }
  return result;
}

std::vector<Ordering> MakeOrderings(const OrderingBridgeVector& orderings) {
  std::vector<Ordering> result;
  result.reserve(orderings.size());
  for (const auto& ordering : orderings) {
    result.push_back(PipelineAccess::Get(ordering));
  }
  return result;
}

std::vector<std::shared_ptr<Stage>> MakeStages(
    const StageBridgeVector& stages) {
  std::vector<std::shared_ptr<Stage>> result;
  result.reserve(stages.size());
  for (const auto& stage : stages) {
    result.push_back(PipelineAccess::Get(stage));
  }
  return result;
}

/// Aborts, as upstream throws, if `firestore` isn't the pipeline's database.
void ValidateSameDatabase(const Firestore& firestore, const Firestore& db,
                          const char* kind) {
  const auto& actual = firestore.database_id();
  const auto& expected = db.database_id();
  if (actual != expected) {
    // Upstream prints the project ID for the expected database too.
    ThrowInvalidArgument(
        "Invalid %s. The project ID (\"%s\") or the database (\"%s\") does not "
        "match the project ID (\"%s\") and database (\"%s\") of the target "
        "database of this Pipeline.",
        kind, actual.project_id(), actual.database_id(), expected.project_id(),
        expected.database_id());
  }
}

std::shared_ptr<void> OwnContext(void* context,
                                 ContextReleaseCallback release) {
  return std::shared_ptr<void>(context, [release](void* context) {
    if (release && context) release(context);
  });
}

void ReportError(PipelineSnapshotCallback callback, void* context,
                 const Status& status) {
  callback(context, nullptr, StatusErrorCode(status),
           status.error_message().c_str());
}

}  // namespace

// ===========================================================================
// ExprBridge
// ===========================================================================

ExprBridge::ExprBridge() noexcept = default;
ExprBridge::~ExprBridge() noexcept = default;
ExprBridge::ExprBridge(const ExprBridge&) noexcept = default;
ExprBridge& ExprBridge::operator=(const ExprBridge&) noexcept = default;
ExprBridge::ExprBridge(ExprBridge&&) noexcept = default;
ExprBridge& ExprBridge::operator=(ExprBridge&&) noexcept = default;

ExprBridge ExprBridge::Field(const FieldPathSegments& field_path) noexcept {
  // Upstream builds the field from the path's canonical string, which it then
  // splits at dots again; the segments keep a segment with a dot intact.
  return PipelineAccess::MakeExpr(std::make_shared<api::Field>(
      FieldPath(field_path.begin(), field_path.end())));
}

std::string ExprBridge::CanonicalFieldPath(
    const FieldPathSegments& field_path) noexcept {
  return FieldPath(field_path.begin(), field_path.end()).CanonicalString();
}

ExprBridge ExprBridge::Constant(const BridgeFieldValue& value,
                                const FirestoreBridge& firestore) noexcept {
  return PipelineAccess::MakeExpr(
      std::make_shared<api::Constant>(nanopb::SharedMessage<google_firestore_v1_Value>(
          ParseQueryValue(BridgeAccess::GetFirestore(firestore), value))));
}

ExprBridge ExprBridge::Variable(const std::string& name) noexcept {
  return PipelineAccess::MakeExpr(std::make_shared<api::Variable>(name));
}

ExprBridge ExprBridge::Function(const std::string& name,
                                const ExprBridgeVector& args,
                                const NamedExprBridges& options) noexcept {
  return PipelineAccess::MakeExpr(std::make_shared<api::FunctionExpr>(
      name, MakeExprs(args), MakeExprMap(options)));
}

ExprBridge ExprBridge::Pipeline(const StageBridgeVector& stages) noexcept {
  return PipelineAccess::MakeExpr(
      std::make_shared<api::PipelineExpr>(MakeStages(stages)));
}

// ===========================================================================
// AggregateFunctionBridge, OrderingBridge, RawStageParamBridge
// ===========================================================================

AggregateFunctionBridge::AggregateFunctionBridge() noexcept = default;
AggregateFunctionBridge::~AggregateFunctionBridge() noexcept = default;
AggregateFunctionBridge::AggregateFunctionBridge(
    const AggregateFunctionBridge&) noexcept = default;
AggregateFunctionBridge& AggregateFunctionBridge::operator=(
    const AggregateFunctionBridge&) noexcept = default;
AggregateFunctionBridge::AggregateFunctionBridge(
    AggregateFunctionBridge&&) noexcept = default;
AggregateFunctionBridge& AggregateFunctionBridge::operator=(
    AggregateFunctionBridge&&) noexcept = default;

AggregateFunctionBridge AggregateFunctionBridge::Create(
    const std::string& name, const ExprBridgeVector& args) noexcept {
  AggregateFunctionBridge result;
  result.function_ =
      std::make_shared<api::AggregateFunction>(name, MakeExprs(args));
  return result;
}

OrderingBridge::OrderingBridge() noexcept = default;
OrderingBridge::~OrderingBridge() noexcept = default;
OrderingBridge::OrderingBridge(const OrderingBridge&) noexcept = default;
OrderingBridge& OrderingBridge::operator=(const OrderingBridge&) noexcept =
    default;
OrderingBridge::OrderingBridge(OrderingBridge&&) noexcept = default;
OrderingBridge& OrderingBridge::operator=(OrderingBridge&&) noexcept = default;

OrderingBridge OrderingBridge::Create(const ExprBridge& expr,
                                      const std::string& direction) noexcept {
  OrderingBridge result;
  result.ordering_ = std::make_shared<Ordering>(
      PipelineAccess::Get(expr), Ordering::DirectionFromString(direction));
  return result;
}

struct RawStageParamBridge::Impl {
  // `api::`: in this scope, `Expr` is RawStageParamBridge::Expr.
  std::shared_ptr<api::Expr> expr;
  std::shared_ptr<api::AggregateFunction> aggregate;
  // A map when neither is set.
  std::vector<std::string> keys;
  RawStageParamBridgeVector values;

  google_firestore_v1_Value ToProto() const {
    if (expr) return expr->to_proto();
    if (aggregate) return aggregate->to_proto();

    google_firestore_v1_Value result{};
    result.which_value_type = google_firestore_v1_Value_map_value_tag;
    std::vector<size_t> indexes(keys.size());
    for (size_t i = 0; i < indexes.size(); ++i) indexes[i] = i;
    nanopb::SetRepeatedField(
        &result.map_value.fields, &result.map_value.fields_count, indexes,
        [this](size_t i) {
          const auto& value = PipelineAccess::Get(values[i]);
          if (!value->expr && !value->aggregate) {
            ThrowInvalidArgument(
                "Dictionary value must be an __FIRExprBridge or "
                "__FIRAggregateFunctionBridge.");
          }
          return google_firestore_v1_MapValue_FieldsEntry{
              nanopb::MakeBytesArray(keys[i]), value->ToProto()};
        });
    return result;
  }
};

RawStageParamBridge::RawStageParamBridge() noexcept = default;
RawStageParamBridge::~RawStageParamBridge() noexcept = default;
RawStageParamBridge::RawStageParamBridge(const RawStageParamBridge&) noexcept =
    default;
RawStageParamBridge& RawStageParamBridge::operator=(
    const RawStageParamBridge&) noexcept = default;
RawStageParamBridge::RawStageParamBridge(RawStageParamBridge&&) noexcept =
    default;
RawStageParamBridge& RawStageParamBridge::operator=(
    RawStageParamBridge&&) noexcept = default;

RawStageParamBridge RawStageParamBridge::Expr(const ExprBridge& expr) noexcept {
  RawStageParamBridge result;
  result.impl_ = std::make_shared<Impl>();
  result.impl_->expr = PipelineAccess::Get(expr);
  return result;
}

RawStageParamBridge RawStageParamBridge::Aggregate(
    const AggregateFunctionBridge& function) noexcept {
  RawStageParamBridge result;
  result.impl_ = std::make_shared<Impl>();
  result.impl_->aggregate = PipelineAccess::Get(function);
  return result;
}

RawStageParamBridge RawStageParamBridge::Map(
    const std::vector<std::string>& keys,
    const RawStageParamBridgeVector& values) noexcept {
  HARD_ASSERT(keys.size() == values.size(), "Keys and values differ in size");
  RawStageParamBridge result;
  result.impl_ = std::make_shared<Impl>();
  result.impl_->keys = keys;
  result.impl_->values = values;
  return result;
}

// ===========================================================================
// StageBridge
// ===========================================================================

StageBridge::StageBridge() noexcept = default;
StageBridge::~StageBridge() noexcept = default;
StageBridge::StageBridge(const StageBridge&) noexcept = default;
StageBridge& StageBridge::operator=(const StageBridge&) noexcept = default;
StageBridge::StageBridge(StageBridge&&) noexcept = default;
StageBridge& StageBridge::operator=(StageBridge&&) noexcept = default;

std::string StageBridge::name() const noexcept {
  return stage_ ? stage_->name() : std::string();
}

StageBridge StageBridge::Collection(const CollectionReferenceBridge& collection,
                                    const FirestoreBridge& firestore,
                                    const std::string& force_index) noexcept {
  const auto& query = BridgeAccess::GetQuery(collection);
  ValidateSameDatabase(*query.firestore(),
                       *BridgeAccess::GetFirestore(firestore),
                       "CollectionReference");
  return PipelineAccess::MakeStage(std::make_shared<api::CollectionSource>(
      EnsureLeadingSlash(collection.path()), OptionalString(force_index)));
}

StageBridge StageBridge::Subcollection(const std::string& path) noexcept {
  return PipelineAccess::MakeStage(
      std::make_shared<api::SubcollectionSource>(path));
}

StageBridge StageBridge::Database() noexcept {
  return PipelineAccess::MakeStage(std::make_shared<api::DatabaseSource>());
}

StageBridge StageBridge::CollectionGroup(
    const std::string& collection_id, const std::string& force_index) noexcept {
  return PipelineAccess::MakeStage(std::make_shared<api::CollectionGroupSource>(
      collection_id, OptionalString(force_index)));
}

StageBridge StageBridge::Documents(const DocumentReferenceBridgeVector& documents,
                                   const FirestoreBridge& firestore) noexcept {
  const auto& db = BridgeAccess::GetFirestore(firestore);
  std::vector<std::string> paths;
  paths.reserve(documents.size());
  for (const auto& document : documents) {
    const auto& reference = BridgeAccess::GetDocumentReference(document);
    ValidateSameDatabase(*reference.firestore(), *db, "DocumentReference");
    paths.push_back(EnsureLeadingSlash(reference.Path()));
  }
  return PipelineAccess::MakeStage(std::make_shared<api::DocumentsSource>(paths));
}

StageBridge StageBridge::Literals(
    const NamedExprBridgesVector& documents) noexcept {
  std::vector<ExprMap> data;
  data.reserve(documents.size());
  for (const auto& document : documents) {
    data.push_back(MakeExprMap(document));
  }
  return PipelineAccess::MakeStage(
      std::make_shared<api::LiteralsSource>(std::move(data)));
}

StageBridge StageBridge::Where(const ExprBridge& condition) noexcept {
  return PipelineAccess::MakeStage(
      std::make_shared<api::Where>(PipelineAccess::Get(condition)));
}

StageBridge StageBridge::Limit(int32_t limit) noexcept {
  return PipelineAccess::MakeStage(std::make_shared<api::LimitStage>(limit));
}

StageBridge StageBridge::Offset(int32_t offset) noexcept {
  return PipelineAccess::MakeStage(std::make_shared<api::OffsetStage>(offset));
}

StageBridge StageBridge::AddFields(const NamedExprBridges& fields) noexcept {
  return PipelineAccess::MakeStage(
      std::make_shared<api::AddFields>(MakeExprMap(fields)));
}

StageBridge StageBridge::RemoveFields(const FieldPathVector& fields) noexcept {
  std::vector<api::Field> cpp_fields;
  cpp_fields.reserve(fields.size());
  for (const auto& segments : fields) {
    cpp_fields.emplace_back(FieldPath(segments.begin(), segments.end()));
  }
  return PipelineAccess::MakeStage(
      std::make_shared<api::RemoveFieldsStage>(std::move(cpp_fields)));
}

StageBridge StageBridge::Select(const NamedExprBridges& selections) noexcept {
  return PipelineAccess::MakeStage(
      std::make_shared<api::SelectStage>(MakeExprMap(selections)));
}

StageBridge StageBridge::Define(const NamedExprBridges& variables) noexcept {
  return PipelineAccess::MakeStage(
      std::make_shared<api::DefineStage>(MakeExprMap(variables)));
}

StageBridge StageBridge::Distinct(const NamedExprBridges& groups) noexcept {
  return PipelineAccess::MakeStage(
      std::make_shared<api::DistinctStage>(MakeExprMap(groups)));
}

StageBridge StageBridge::Aggregate(
    const NamedAggregateFunctionBridges& accumulators,
    const NamedExprBridges& groups) noexcept {
  std::unordered_map<std::string, std::shared_ptr<api::AggregateFunction>>
      cpp_accumulators;
  for (const auto& entry : accumulators) {
    cpp_accumulators[entry.first] = PipelineAccess::Get(entry.second);
  }
  return PipelineAccess::MakeStage(std::make_shared<api::AggregateStage>(
      std::move(cpp_accumulators), MakeExprMap(groups)));
}

StageBridge StageBridge::FindNearest(const ExprBridge& field,
                                     const BridgeFieldValue& vector,
                                     const std::string& distance_measure,
                                     bool has_limit,
                                     int64_t limit,
                                     bool has_distance_field,
                                     const ExprBridge& distance_field,
                                     const FirestoreBridge& firestore) noexcept {
  const auto& db = BridgeAccess::GetFirestore(firestore);
  std::unordered_map<std::string, google_firestore_v1_Value> options;
  if (has_limit) {
    options.emplace("limit",
                    *ParseQueryValue(db, BridgeFieldValue::FromInt64(limit))
                         .release());
  }
  if (has_distance_field) {
    options.emplace("distance_field",
                    PipelineAccess::Get(distance_field)->to_proto());
  }

  using Measure = api::FindNearestStage::DistanceMeasure;
  Measure::Measure measure = Measure::EUCLIDEAN;
  if (distance_measure == "cosine") {
    measure = Measure::COSINE;
  } else if (distance_measure == "dot_product") {
    measure = Measure::DOT_PRODUCT;
  }

  return PipelineAccess::MakeStage(std::make_shared<api::FindNearestStage>(
      PipelineAccess::Get(field),
      nanopb::SharedMessage<google_firestore_v1_Value>(
          ParseQueryValue(db, vector)),
      Measure(measure), std::move(options)));
}

StageBridge StageBridge::Search(const NamedExprBridges& options,
                                const NamedExprBridges& add_fields,
                                const NamedExprBridges& select,
                                const OrderingBridgeVector& sort) noexcept {
  return PipelineAccess::MakeStage(std::make_shared<api::SearchStage>(
      MakeExprMap(options), MakeExprMap(add_fields), MakeExprMap(select),
      MakeOrderings(sort)));
}

StageBridge StageBridge::Sort(const OrderingBridgeVector& orderings) noexcept {
  return PipelineAccess::MakeStage(
      std::make_shared<api::SortStage>(MakeOrderings(orderings)));
}

StageBridge StageBridge::ReplaceWith(const ExprBridge& expr) noexcept {
  return PipelineAccess::MakeStage(
      std::make_shared<api::ReplaceWith>(PipelineAccess::Get(expr)));
}

StageBridge StageBridge::SampleCount(int64_t count) noexcept {
  using Mode = api::Sample::SampleMode;
  return PipelineAccess::MakeStage(
      std::make_shared<api::Sample>(Mode(Mode::DOCUMENTS), count, 0));
}

StageBridge StageBridge::SamplePercentage(double percentage) noexcept {
  using Mode = api::Sample::SampleMode;
  return PipelineAccess::MakeStage(
      std::make_shared<api::Sample>(Mode(Mode::PERCENT), 0, percentage));
}

StageBridge StageBridge::Union(const PipelineBridge& other) noexcept {
  return PipelineAccess::MakeStage(
      std::make_shared<api::Union>(PipelineAccess::Get(other)));
}

StageBridge StageBridge::Unnest(const ExprBridge& field,
                                const ExprBridge& alias,
                                bool has_index_field,
                                const ExprBridge& index_field) noexcept {
  absl::optional<std::shared_ptr<Expr>> cpp_index_field;
  if (has_index_field) cpp_index_field = PipelineAccess::Get(index_field);
  return PipelineAccess::MakeStage(std::make_shared<api::Unnest>(
      PipelineAccess::Get(field), PipelineAccess::Get(alias),
      std::move(cpp_index_field)));
}

StageBridge StageBridge::Raw(const std::string& name,
                             const RawStageParamBridgeVector& params,
                             const NamedExprBridges& options) noexcept {
  std::vector<google_firestore_v1_Value> cpp_params;
  cpp_params.reserve(params.size());
  for (const auto& param : params) {
    cpp_params.push_back(PipelineAccess::Get(param)->ToProto());
  }
  return PipelineAccess::MakeStage(std::make_shared<api::RawStage>(
      name, std::move(cpp_params), MakeExprMap(options)));
}

StageBridge StageBridge::Delete() noexcept {
  return PipelineAccess::MakeStage(std::make_shared<api::DeleteStage>());
}

StageBridge StageBridge::Update(const NamedExprBridges& fields) noexcept {
  return PipelineAccess::MakeStage(
      std::make_shared<api::UpdateStage>(MakeExprMap(fields)));
}

StageBridge StageBridge::Insert(const std::string& collection_path,
                                bool has_document_id,
                                const ExprBridge& document_id) noexcept {
  return PipelineAccess::MakeStage(std::make_shared<api::InsertStage>(
      collection_path,
      has_document_id ? PipelineAccess::Get(document_id) : nullptr));
}

StageBridge StageBridge::Upsert(const NamedExprBridges& fields,
                                const std::string& collection_path,
                                bool has_document_id,
                                const ExprBridge& document_id) noexcept {
  return PipelineAccess::MakeStage(std::make_shared<api::UpsertStage>(
      MakeExprMap(fields), collection_path,
      has_document_id ? PipelineAccess::Get(document_id) : nullptr));
}

StageBridgeVector StageBridge::FromQuery(const QueryBridge& query) noexcept {
  StageBridgeVector result;
  for (auto& stage :
       core::ToPipelineStages(BridgeAccess::GetQuery(query).query())) {
    const auto& name = stage->name();
    // The stages upstream's `createStageBridgesFromQuery:` can represent.
    if (name != "collection" && name != "collection_group" &&
        name != "documents" && name != "where" && name != "limit" &&
        name != "sort" && name != "offset") {
      ThrowInvalidArgument(
          "Unknown or unhandled stage type '%s' encountered when converting "
          "from FIRQuery.",
          name);
    }
    result.push_back(PipelineAccess::MakeStage(std::move(stage)));
  }
  return result;
}

// ===========================================================================
// Results
// ===========================================================================

struct PipelineResultBridge::Impl {
  Impl(api::PipelineResult result, std::shared_ptr<Firestore> firestore)
      : result_(std::move(result)), firestore_(std::move(firestore)) {}
  api::PipelineResult result_;
  std::shared_ptr<Firestore> firestore_;
};

PipelineResultBridge PipelineAccess::MakeResult(
    api::PipelineResult result, std::shared_ptr<Firestore> firestore) {
  PipelineResultBridge bridge;
  bridge.impl_ = std::make_shared<PipelineResultBridge::Impl>(
      std::move(result), std::move(firestore));
  return bridge;
}

PipelineResultBridge::PipelineResultBridge() noexcept = default;
PipelineResultBridge::~PipelineResultBridge() noexcept = default;
PipelineResultBridge::PipelineResultBridge(const PipelineResultBridge&) noexcept =
    default;
PipelineResultBridge& PipelineResultBridge::operator=(
    const PipelineResultBridge&) noexcept = default;
PipelineResultBridge::PipelineResultBridge(PipelineResultBridge&&) noexcept =
    default;
PipelineResultBridge& PipelineResultBridge::operator=(
    PipelineResultBridge&&) noexcept = default;

bool PipelineResultBridge::GetReference(
    DocumentReferenceBridge& reference) const noexcept {
  if (!impl_ || !impl_->result_.internal_key().has_value()) return false;
  reference = BridgeAccess::MakeDocumentReference(api::DocumentReference(
      impl_->result_.internal_key().value(), impl_->firestore_));
  return true;
}

bool PipelineResultBridge::has_document_id() const noexcept {
  return impl_ && impl_->result_.document_id().has_value();
}

std::string PipelineResultBridge::document_id() const noexcept {
  if (!has_document_id()) return std::string();
  return std::string(impl_->result_.document_id().value());
}

bool PipelineResultBridge::has_create_time() const noexcept {
  return impl_ && impl_->result_.create_time().has_value();
}

int64_t PipelineResultBridge::create_time_seconds() const noexcept {
  if (!has_create_time()) return 0;
  return impl_->result_.create_time()->timestamp().seconds();
}

int32_t PipelineResultBridge::create_time_nanos() const noexcept {
  if (!has_create_time()) return 0;
  return impl_->result_.create_time()->timestamp().nanoseconds();
}

bool PipelineResultBridge::has_update_time() const noexcept {
  return impl_ && impl_->result_.update_time().has_value();
}

int64_t PipelineResultBridge::update_time_seconds() const noexcept {
  if (!has_update_time()) return 0;
  return impl_->result_.update_time()->timestamp().seconds();
}

int32_t PipelineResultBridge::update_time_nanos() const noexcept {
  if (!has_update_time()) return 0;
  return impl_->result_.update_time()->timestamp().nanoseconds();
}

BridgeFieldValueMap PipelineResultBridge::data(
    int32_t server_timestamp_behavior) const noexcept {
  if (!impl_) return BridgeFieldValueMap{};
  google_firestore_v1_Value data = impl_->result_.internal_value()->Get();
  if (data.which_value_type != google_firestore_v1_Value_map_value_tag) {
    return BridgeFieldValueMap{};
  }
  return ConvertValueForSwift(data, impl_->firestore_,
                              server_timestamp_behavior)
      .map_value();
}

bool PipelineResultBridge::GetField(const FieldPathSegments& field_path,
                                    int32_t server_timestamp_behavior,
                                    BridgeFieldValue& value) const noexcept {
  if (!impl_) return false;
  auto field = impl_->result_.internal_value()->Get(
      FieldPath(field_path.begin(), field_path.end()));
  if (!field) return false;
  value = ConvertValueForSwift(*field, impl_->firestore_,
                               server_timestamp_behavior);
  return true;
}

PipelineSnapshotBridge::PipelineSnapshotBridge() noexcept = default;
PipelineSnapshotBridge::~PipelineSnapshotBridge() noexcept = default;
PipelineSnapshotBridge::PipelineSnapshotBridge(
    const PipelineSnapshotBridge&) noexcept = default;
PipelineSnapshotBridge& PipelineSnapshotBridge::operator=(
    const PipelineSnapshotBridge&) noexcept = default;
PipelineSnapshotBridge::PipelineSnapshotBridge(
    PipelineSnapshotBridge&&) noexcept = default;
PipelineSnapshotBridge& PipelineSnapshotBridge::operator=(
    PipelineSnapshotBridge&&) noexcept = default;

PipelineResultBridgeVector PipelineSnapshotBridge::results() const noexcept {
  PipelineResultBridgeVector results;
  if (!snapshot_) return results;
  for (const auto& result : snapshot_->results()) {
    results.push_back(PipelineAccess::MakeResult(result, snapshot_->firestore()));
  }
  return results;
}

int64_t PipelineSnapshotBridge::execution_time_seconds() const noexcept {
  return snapshot_ ? snapshot_->execution_time().timestamp().seconds() : 0;
}

int32_t PipelineSnapshotBridge::execution_time_nanos() const noexcept {
  return snapshot_ ? snapshot_->execution_time().timestamp().nanoseconds() : 0;
}

PipelineResultChangeBridge::PipelineResultChangeBridge() noexcept = default;
PipelineResultChangeBridge::~PipelineResultChangeBridge() noexcept = default;
PipelineResultChangeBridge::PipelineResultChangeBridge(
    const PipelineResultChangeBridge&) noexcept = default;
PipelineResultChangeBridge& PipelineResultChangeBridge::operator=(
    const PipelineResultChangeBridge&) noexcept = default;
PipelineResultChangeBridge::PipelineResultChangeBridge(
    PipelineResultChangeBridge&&) noexcept = default;
PipelineResultChangeBridge& PipelineResultChangeBridge::operator=(
    PipelineResultChangeBridge&&) noexcept = default;

PipelineResultChangeBridge::Type PipelineResultChangeBridge::type()
    const noexcept {
  switch (change_->type()) {
    case api::PipelineResultChange::Type::Added:
      return Type::Added;
    case api::PipelineResultChange::Type::Modified:
      return Type::Modified;
    case api::PipelineResultChange::Type::Removed:
      return Type::Removed;
  }
  UNREACHABLE();
}

PipelineResultBridge PipelineResultChangeBridge::result() const noexcept {
  return PipelineAccess::MakeResult(change_->result(), firestore_);
}

int64_t PipelineResultChangeBridge::old_index() const noexcept {
  auto index = change_->old_index();
  return index == api::PipelineResultChange::npos ? -1
                                                  : static_cast<int64_t>(index);
}

int64_t PipelineResultChangeBridge::new_index() const noexcept {
  auto index = change_->new_index();
  return index == api::PipelineResultChange::npos ? -1
                                                  : static_cast<int64_t>(index);
}

RealtimePipelineSnapshotBridge::RealtimePipelineSnapshotBridge() noexcept =
    default;
RealtimePipelineSnapshotBridge::~RealtimePipelineSnapshotBridge() noexcept =
    default;
RealtimePipelineSnapshotBridge::RealtimePipelineSnapshotBridge(
    const RealtimePipelineSnapshotBridge&) noexcept = default;
RealtimePipelineSnapshotBridge& RealtimePipelineSnapshotBridge::operator=(
    const RealtimePipelineSnapshotBridge&) noexcept = default;
RealtimePipelineSnapshotBridge::RealtimePipelineSnapshotBridge(
    RealtimePipelineSnapshotBridge&&) noexcept = default;
RealtimePipelineSnapshotBridge& RealtimePipelineSnapshotBridge::operator=(
    RealtimePipelineSnapshotBridge&&) noexcept = default;

PipelineResultBridgeVector RealtimePipelineSnapshotBridge::results()
    const noexcept {
  PipelineResultBridgeVector results;
  if (!snapshot_) return results;
  for (const auto& document : snapshot_->view_snapshot().documents()) {
    results.push_back(PipelineAccess::MakeResult(api::PipelineResult(document),
                                                 snapshot_->firestore()));
  }
  return results;
}

PipelineResultChangeBridgeVector RealtimePipelineSnapshotBridge::changes()
    const noexcept {
  PipelineResultChangeBridgeVector changes;
  if (!snapshot_) return changes;
  // As upstream: without metadata-only changes.
  for (auto& change : snapshot_->CalculateResultChanges(false)) {
    changes.push_back(
        PipelineAccess::MakeChange(std::move(change), snapshot_->firestore()));
  }
  return changes;
}

api::SnapshotMetadata RealtimePipelineSnapshotBridge::metadata()
    const noexcept {
  return snapshot_ ? snapshot_->snapshot_metadata() : api::SnapshotMetadata();
}

// ===========================================================================
// PipelineBridge
// ===========================================================================

PipelineBridge::PipelineBridge() noexcept = default;
PipelineBridge::~PipelineBridge() noexcept = default;
PipelineBridge::PipelineBridge(const PipelineBridge&) noexcept = default;
PipelineBridge& PipelineBridge::operator=(const PipelineBridge&) noexcept =
    default;
PipelineBridge::PipelineBridge(PipelineBridge&&) noexcept = default;
PipelineBridge& PipelineBridge::operator=(PipelineBridge&&) noexcept = default;

PipelineBridge PipelineBridge::Create(const StageBridgeVector& stages,
                                      const FirestoreBridge& firestore,
                                      bool atomic) noexcept {
  return PipelineAccess::MakePipeline(std::make_shared<api::Pipeline>(
      MakeStages(stages), BridgeAccess::GetFirestore(firestore), atomic));
}

void PipelineBridge::Execute(void* context,
                             PipelineSnapshotCallback callback) const noexcept {
  pipeline_->execute(
      [context, callback](StatusOr<api::PipelineSnapshot> maybe_snapshot) {
        if (!maybe_snapshot.ok()) {
          ReportError(callback, context, maybe_snapshot.status());
          return;
        }
        callback(context,
                 PipelineAccess::NewSnapshot(
                     std::move(maybe_snapshot).ValueOrDie()),
                 0, "");
      });
}

namespace {

core::ListenOptions MakeListenOptions(bool include_metadata_changes,
                                      int32_t listen_source,
                                      int32_t server_timestamp_behavior) {
  using Behavior = core::ListenOptions::ServerTimestampBehavior;
  Behavior behavior = Behavior::kNone;
  if (server_timestamp_behavior == 1) {
    behavior = Behavior::kEstimate;
  } else if (server_timestamp_behavior == 2) {
    behavior = Behavior::kPrevious;
  }
  return core::ListenOptions(
      /*include_query_metadata_changes=*/include_metadata_changes,
      /*include_document_metadata_changes=*/include_metadata_changes,
      /*wait_for_sync_when_online=*/false,
      listen_source == 1 ? core::ListenSource::Cache
                         : core::ListenSource::Default,
      behavior);
}

}  // namespace

ListenerRegistrationBridge PipelineBridge::AddRealtimeSnapshotListener(
    const StageBridgeVector& stages,
    const FirestoreBridge& firestore,
    bool include_metadata_changes,
    int32_t listen_source,
    int32_t server_timestamp_behavior,
    void* context,
    ContextReleaseCallback release_context,
    PipelineSnapshotCallback callback) noexcept {
  std::shared_ptr<Firestore> db = BridgeAccess::GetFirestore(firestore);

  std::vector<std::shared_ptr<api::EvaluableStage>> evaluable_stages;
  for (const auto& stage : stages) {
    auto evaluable_stage =
        std::dynamic_pointer_cast<api::EvaluableStage>(PipelineAccess::Get(stage));
    if (!evaluable_stage) {
      HARD_FAIL(
          "Failed to convert cpp stage to EvaluableStage for RealtimePipeline");
    }
    evaluable_stages.push_back(std::move(evaluable_stage));
  }
  api::RealtimePipeline pipeline(
      std::move(evaluable_stages),
      std::make_unique<remote::Serializer>(db->database_id()));

  auto view_listener = core::EventListener<core::ViewSnapshot>::Create(
      [owned = OwnContext(context, release_context), callback,
       db](StatusOr<core::ViewSnapshot> maybe_snapshot) {
        if (!maybe_snapshot.ok()) {
          ReportError(callback, owned.get(), maybe_snapshot.status());
          return;
        }
        core::ViewSnapshot snapshot = std::move(maybe_snapshot).ValueOrDie();
        api::SnapshotMetadata metadata(snapshot.has_pending_writes(),
                                       snapshot.from_cache());
        callback(owned.get(),
                 PipelineAccess::NewSnapshot(api::RealtimePipelineSnapshot(
                     db, std::move(snapshot), metadata)),
                 0, "");
      });

  // `client()` requires a configured client; getting a batch configures it,
  // as getting a collection does before a query listens.
  db->GetBatch();
  const auto& client = db->client();
  auto async_listener = core::AsyncEventListener<core::ViewSnapshot>::Create(
      client->user_executor(), std::move(view_listener));
  auto query_listener = client->ListenToQuery(
      core::QueryOrPipeline(std::move(pipeline)),
      MakeListenOptions(include_metadata_changes, listen_source,
                        server_timestamp_behavior),
      async_listener);
  return BridgeAccess::MakeListenerRegistration(
      std::make_unique<api::QueryListenerRegistration>(
          client, std::move(async_listener), std::move(query_listener)));
}

}  // namespace swift_bridge
}  // namespace firestore
}  // namespace firebase
