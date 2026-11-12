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

#ifndef PIPELINE_BRIDGE_H_
#define PIPELINE_BRIDGE_H_

// The pipeline part of the Swift bridge: what upstream's FIRPipelineBridge.mm
// does for Objective-C. Swift builds expressions and stages from these value
// types when a pipeline runs; they wrap the core's `api::Expr`, `api::Stage`
// and `api::Pipeline`.

#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "FirestoreBridge.h"

/// Callback for pipeline results.
/// snapshot: opaque pointer to a heap-allocated PipelineSnapshotBridge (or,
/// for realtime pipelines, RealtimePipelineSnapshotBridge) that the caller
/// owns, or null on error.
typedef void (*PipelineSnapshotCallback)(
    void* context,
    void* snapshot,
    int32_t error_code,
    const char* error_message);

namespace firebase {
namespace firestore {
namespace api {
class AggregateFunction;
class Expr;
class Ordering;
class Pipeline;
class PipelineResult;
class PipelineResultChange;
class PipelineSnapshot;
class RealtimePipelineSnapshot;
class Stage;
}  // namespace api

namespace swift_bridge {

class ExprBridge;
class AggregateFunctionBridge;
class OrderingBridge;
class WindowValueBridge;
class WindowSpecBridge;
class StageBridge;
class PipelineBridge;
class PipelineResultBridge;
class PipelineResultChangeBridge;

using ExprBridgeVector = std::vector<ExprBridge>;
/// Expressions by name (aliases, options, map fields), in order.
using NamedExprBridge = std::pair<std::string, ExprBridge>;
using NamedExprBridges = std::vector<NamedExprBridge>;
/// The documents of a `literals` stage.
using NamedExprBridgesVector = std::vector<NamedExprBridges>;
using NamedAggregateFunctionBridge =
    std::pair<std::string, AggregateFunctionBridge>;
using NamedAggregateFunctionBridges = std::vector<NamedAggregateFunctionBridge>;
using OrderingBridgeVector = std::vector<OrderingBridge>;
using StageBridgeVector = std::vector<StageBridge>;
using DocumentReferenceBridgeVector = std::vector<DocumentReferenceBridge>;
using PipelineResultBridgeVector = std::vector<PipelineResultBridge>;
using PipelineResultChangeBridgeVector =
    std::vector<PipelineResultChangeBridge>;

/// A raw stage's parameter: an expression, an aggregate function, or a map
/// of them (upstream's `__FIRRawStageBridge` accepts the same).
class RawStageParamBridge;
using RawStageParamBridgeVector = std::vector<RawStageParamBridge>;

// ---------------------------------------------------------------------------
// ExprBridge
// ---------------------------------------------------------------------------
/// Wraps `api::Expr`.
class ExprBridge {
 public:
  ExprBridge() noexcept;
  ~ExprBridge() noexcept;
  ExprBridge(const ExprBridge&) noexcept;
  ExprBridge& operator=(const ExprBridge&) noexcept;
  ExprBridge(ExprBridge&&) noexcept;
  ExprBridge& operator=(ExprBridge&&) noexcept;

  static ExprBridge Field(const FieldPathSegments& field_path) noexcept;
  /// A field path's canonical string, e.g. "a.`b.c`", which names the
  /// field in results.
  static std::string CanonicalFieldPath(
      const FieldPathSegments& field_path) noexcept;
  /// A constant, parsed as a query value (as upstream's `parsedQueryValue:`);
  /// invalid values abort with upstream's messages.
  static ExprBridge Constant(const BridgeFieldValue& value,
                             const FirestoreBridge& firestore) noexcept;
  static ExprBridge Variable(const std::string& name) noexcept;
  static ExprBridge Function(const std::string& name,
                             const ExprBridgeVector& args,
                             const NamedExprBridges& options) noexcept;
  /// A subpipeline used as an expression.
  static ExprBridge Pipeline(const StageBridgeVector& stages) noexcept;

 private:
  friend struct PipelineAccess;
  std::shared_ptr<api::Expr> expr_;
};

// ---------------------------------------------------------------------------
// WindowValueBridge, WindowSpecBridge, AggregateFunctionBridge, OrderingBridge
// ---------------------------------------------------------------------------
/// A window frame's bound or unit: an expression, a string ("unbounded",
/// "current", a unit's name), a number, or none (serialized as null).
class WindowValueBridge {
 public:
  WindowValueBridge() noexcept;
  ~WindowValueBridge() noexcept;
  WindowValueBridge(const WindowValueBridge&) noexcept;
  WindowValueBridge& operator=(const WindowValueBridge&) noexcept;
  WindowValueBridge(WindowValueBridge&&) noexcept;
  WindowValueBridge& operator=(WindowValueBridge&&) noexcept;

  static WindowValueBridge None() noexcept;
  static WindowValueBridge Expr(const ExprBridge& expr) noexcept;
  static WindowValueBridge String(const std::string& value) noexcept;
  static WindowValueBridge Integer(int64_t value) noexcept;
  static WindowValueBridge Double(double value) noexcept;

 private:
  friend struct PipelineAccess;
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

/// A window function's partition, sort and frame (upstream's
/// `__FIRWindowSpecBridge`), which the backend takes as a map value.
class WindowSpecBridge {
 public:
  WindowSpecBridge() noexcept;
  ~WindowSpecBridge() noexcept;
  WindowSpecBridge(const WindowSpecBridge&) noexcept;
  WindowSpecBridge& operator=(const WindowSpecBridge&) noexcept;
  WindowSpecBridge(WindowSpecBridge&&) noexcept;
  WindowSpecBridge& operator=(WindowSpecBridge&&) noexcept;

  /// `type` is the frame's kind ("range" or "documents"), or empty for no
  /// frame; `unit` is left out when it's `None`.
  static WindowSpecBridge Create(const ExprBridgeVector& groups,
                                 const OrderingBridgeVector& sort,
                                 const std::string& type,
                                 const WindowValueBridge& preceding,
                                 const WindowValueBridge& following,
                                 const WindowValueBridge& unit) noexcept;

 private:
  friend struct PipelineAccess;
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

/// Wraps `api::AggregateFunction`, and also a window function: an aggregate
/// framed by a window (sent as `over(function, window)`).
class AggregateFunctionBridge {
 public:
  AggregateFunctionBridge() noexcept;
  ~AggregateFunctionBridge() noexcept;
  AggregateFunctionBridge(const AggregateFunctionBridge&) noexcept;
  AggregateFunctionBridge& operator=(const AggregateFunctionBridge&) noexcept;
  AggregateFunctionBridge(AggregateFunctionBridge&&) noexcept;
  AggregateFunctionBridge& operator=(AggregateFunctionBridge&&) noexcept;

  static AggregateFunctionBridge Create(const std::string& name,
                                        const ExprBridgeVector& args) noexcept;
  static AggregateFunctionBridge Create(const std::string& name,
                                        const ExprBridgeVector& args,
                                        const WindowSpecBridge& window) noexcept;

 private:
  friend struct PipelineAccess;
  std::shared_ptr<api::AggregateFunction> function_;
  /// The window, for a window function.
  std::shared_ptr<WindowSpecBridge> window_;
};

/// Wraps `api::Ordering`.
class OrderingBridge {
 public:
  OrderingBridge() noexcept;
  ~OrderingBridge() noexcept;
  OrderingBridge(const OrderingBridge&) noexcept;
  OrderingBridge& operator=(const OrderingBridge&) noexcept;
  OrderingBridge(OrderingBridge&&) noexcept;
  OrderingBridge& operator=(OrderingBridge&&) noexcept;

  /// `direction` is "ascending" or "descending"; anything else aborts.
  static OrderingBridge Create(const ExprBridge& expr,
                               const std::string& direction) noexcept;

 private:
  friend struct PipelineAccess;
  std::shared_ptr<api::Ordering> ordering_;
};

class RawStageParamBridge {
 public:
  RawStageParamBridge() noexcept;
  ~RawStageParamBridge() noexcept;
  RawStageParamBridge(const RawStageParamBridge&) noexcept;
  RawStageParamBridge& operator=(const RawStageParamBridge&) noexcept;
  RawStageParamBridge(RawStageParamBridge&&) noexcept;
  RawStageParamBridge& operator=(RawStageParamBridge&&) noexcept;

  static RawStageParamBridge Expr(const ExprBridge& expr) noexcept;
  static RawStageParamBridge Aggregate(
      const AggregateFunctionBridge& function) noexcept;
  /// A map whose values are `Expr` or `Aggregate` parameters.
  static RawStageParamBridge Map(const std::vector<std::string>& keys,
                                 const RawStageParamBridgeVector& values) noexcept;

 private:
  friend struct PipelineAccess;
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

// ---------------------------------------------------------------------------
// StageBridge
// ---------------------------------------------------------------------------
/// Wraps `api::Stage`. Optional string arguments are empty when absent.
class StageBridge {
 public:
  StageBridge() noexcept;
  ~StageBridge() noexcept;
  StageBridge(const StageBridge&) noexcept;
  StageBridge& operator=(const StageBridge&) noexcept;
  StageBridge(StageBridge&&) noexcept;
  StageBridge& operator=(StageBridge&&) noexcept;

  /// The stage's name, e.g. "where".
  std::string name() const noexcept;

  // Sources. A collection or document from another database aborts, as
  // upstream.
  static StageBridge Collection(const CollectionReferenceBridge& collection,
                                const FirestoreBridge& firestore,
                                const std::string& force_index) noexcept;
  static StageBridge Subcollection(const std::string& path) noexcept;
  static StageBridge Database() noexcept;
  static StageBridge CollectionGroup(const std::string& collection_id,
                                     const std::string& force_index) noexcept;
  static StageBridge Documents(const DocumentReferenceBridgeVector& documents,
                               const FirestoreBridge& firestore) noexcept;
  static StageBridge Literals(const NamedExprBridgesVector& documents) noexcept;

  static StageBridge Where(const ExprBridge& condition) noexcept;
  static StageBridge Limit(int32_t limit) noexcept;
  static StageBridge Offset(int32_t offset) noexcept;
  static StageBridge AddFields(const NamedExprBridges& fields) noexcept;
  /// Window functions computed over `window` (upstream's
  /// `__FIRAddWindowFieldsStageBridge`, a raw stage).
  static StageBridge AddWindowFields(
      const WindowSpecBridge& window,
      const NamedAggregateFunctionBridges& fields,
      const NamedExprBridges& options) noexcept;
  static StageBridge RemoveFields(const FieldPathVector& fields) noexcept;
  static StageBridge Select(const NamedExprBridges& selections) noexcept;
  static StageBridge Define(const NamedExprBridges& variables) noexcept;
  static StageBridge Distinct(const NamedExprBridges& groups) noexcept;
  static StageBridge Aggregate(const NamedAggregateFunctionBridges& accumulators,
                               const NamedExprBridges& groups) noexcept;
  /// `distance_measure`: "cosine", "dot_product" or (anything else)
  /// "euclidean". `limit` is used when `has_limit`; `distance_field` when
  /// `has_distance_field`.
  static StageBridge FindNearest(const ExprBridge& field,
                                 const BridgeFieldValue& vector,
                                 const std::string& distance_measure,
                                 bool has_limit,
                                 int64_t limit,
                                 bool has_distance_field,
                                 const ExprBridge& distance_field,
                                 const FirestoreBridge& firestore) noexcept;
  static StageBridge Search(const NamedExprBridges& options,
                            const NamedExprBridges& add_fields,
                            const NamedExprBridges& select,
                            const OrderingBridgeVector& sort) noexcept;
  static StageBridge Sort(const OrderingBridgeVector& orderings) noexcept;
  static StageBridge ReplaceWith(const ExprBridge& expr) noexcept;
  static StageBridge SampleCount(int64_t count) noexcept;
  static StageBridge SamplePercentage(double percentage) noexcept;
  static StageBridge Union(const PipelineBridge& other) noexcept;
  /// `index_field` is used when `has_index_field`.
  static StageBridge Unnest(const ExprBridge& field,
                            const ExprBridge& alias,
                            bool has_index_field,
                            const ExprBridge& index_field) noexcept;
  static StageBridge Raw(const std::string& name,
                         const RawStageParamBridgeVector& params,
                         const NamedExprBridges& options) noexcept;

  // Writes (DML).
  static StageBridge Delete() noexcept;
  static StageBridge Update(const NamedExprBridges& fields) noexcept;
  /// `document_id` is used when `has_document_id`.
  static StageBridge Insert(const std::string& collection_path,
                            bool has_document_id,
                            const ExprBridge& document_id) noexcept;
  static StageBridge Upsert(const NamedExprBridges& fields,
                            const std::string& collection_path,
                            bool has_document_id,
                            const ExprBridge& document_id) noexcept;

  /// The stages of a pipeline equivalent to `query`.
  static StageBridgeVector FromQuery(const QueryBridge& query) noexcept;

 private:
  friend struct PipelineAccess;
  std::shared_ptr<api::Stage> stage_;
};

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------
/// Wraps `api::PipelineResult`.
class PipelineResultBridge {
 public:
  PipelineResultBridge() noexcept;
  ~PipelineResultBridge() noexcept;
  PipelineResultBridge(const PipelineResultBridge&) noexcept;
  PipelineResultBridge& operator=(const PipelineResultBridge&) noexcept;
  PipelineResultBridge(PipelineResultBridge&&) noexcept;
  PipelineResultBridge& operator=(PipelineResultBridge&&) noexcept;

  /// Writes the result's document to `reference` and returns true, or returns
  /// false if the result isn't a document.
  bool GetReference(DocumentReferenceBridge& reference) const noexcept;
  bool has_document_id() const noexcept;
  std::string document_id() const noexcept;

  bool has_create_time() const noexcept;
  int64_t create_time_seconds() const noexcept;
  int32_t create_time_nanos() const noexcept;
  bool has_update_time() const noexcept;
  int64_t update_time_seconds() const noexcept;
  int32_t update_time_nanos() const noexcept;

  /// The result's fields. `server_timestamp_behavior` as in
  /// `DocumentSnapshotBridge::data`.
  BridgeFieldValueMap data(int32_t server_timestamp_behavior) const noexcept;
  /// Writes the field's value to `value` and returns true, or returns false
  /// if there's no such field.
  bool GetField(const FieldPathSegments& field_path,
                int32_t server_timestamp_behavior,
                BridgeFieldValue& value) const noexcept;

 private:
  friend struct PipelineAccess;
  struct Impl;
  std::shared_ptr<Impl> impl_;
};

/// Wraps `api::PipelineSnapshot`.
class PipelineSnapshotBridge {
 public:
  PipelineSnapshotBridge() noexcept;
  ~PipelineSnapshotBridge() noexcept;
  PipelineSnapshotBridge(const PipelineSnapshotBridge&) noexcept;
  PipelineSnapshotBridge& operator=(const PipelineSnapshotBridge&) noexcept;
  PipelineSnapshotBridge(PipelineSnapshotBridge&&) noexcept;
  PipelineSnapshotBridge& operator=(PipelineSnapshotBridge&&) noexcept;

  PipelineResultBridgeVector results() const noexcept;
  int64_t execution_time_seconds() const noexcept;
  int32_t execution_time_nanos() const noexcept;

 private:
  friend struct PipelineAccess;
  std::shared_ptr<api::PipelineSnapshot> snapshot_;
};

/// Wraps `api::PipelineResultChange`.
class PipelineResultChangeBridge {
 public:
  /// As `DocumentChangeBridge::Type`.
  enum class Type : int32_t { Added = 0, Modified, Removed };

  PipelineResultChangeBridge() noexcept;
  ~PipelineResultChangeBridge() noexcept;
  PipelineResultChangeBridge(const PipelineResultChangeBridge&) noexcept;
  PipelineResultChangeBridge& operator=(
      const PipelineResultChangeBridge&) noexcept;
  PipelineResultChangeBridge(PipelineResultChangeBridge&&) noexcept;
  PipelineResultChangeBridge& operator=(PipelineResultChangeBridge&&) noexcept;

  Type type() const noexcept;
  PipelineResultBridge result() const noexcept;
  /// -1 when the result wasn't in the previous snapshot.
  int64_t old_index() const noexcept;
  /// -1 when the result was removed.
  int64_t new_index() const noexcept;

 private:
  friend struct PipelineAccess;
  std::shared_ptr<api::PipelineResultChange> change_;
  std::shared_ptr<api::Firestore> firestore_;
};

/// Wraps `api::RealtimePipelineSnapshot`.
class RealtimePipelineSnapshotBridge {
 public:
  RealtimePipelineSnapshotBridge() noexcept;
  ~RealtimePipelineSnapshotBridge() noexcept;
  RealtimePipelineSnapshotBridge(const RealtimePipelineSnapshotBridge&) noexcept;
  RealtimePipelineSnapshotBridge& operator=(
      const RealtimePipelineSnapshotBridge&) noexcept;
  RealtimePipelineSnapshotBridge(RealtimePipelineSnapshotBridge&&) noexcept;
  RealtimePipelineSnapshotBridge& operator=(
      RealtimePipelineSnapshotBridge&&) noexcept;

  PipelineResultBridgeVector results() const noexcept;
  PipelineResultChangeBridgeVector changes() const noexcept;
  api::SnapshotMetadata metadata() const noexcept;

 private:
  friend struct PipelineAccess;
  std::shared_ptr<api::RealtimePipelineSnapshot> snapshot_;
};

// ---------------------------------------------------------------------------
// PipelineBridge
// ---------------------------------------------------------------------------
/// Wraps `api::Pipeline`.
class PipelineBridge {
 public:
  PipelineBridge() noexcept;
  ~PipelineBridge() noexcept;
  PipelineBridge(const PipelineBridge&) noexcept;
  PipelineBridge& operator=(const PipelineBridge&) noexcept;
  PipelineBridge(PipelineBridge&&) noexcept;
  PipelineBridge& operator=(PipelineBridge&&) noexcept;

  static PipelineBridge Create(const StageBridgeVector& stages,
                               const FirestoreBridge& firestore,
                               bool atomic) noexcept;

  /// Runs the pipeline on the server; `callback` gets a
  /// PipelineSnapshotBridge.
  void Execute(void* context, PipelineSnapshotCallback callback) const noexcept;

  /// Listens to a realtime pipeline of `stages`, which must all be stages a
  /// realtime pipeline supports (else this aborts, as upstream). `callback`
  /// gets RealtimePipelineSnapshotBridges. `listen_source`: 0 = default,
  /// 1 = cache. `release_context` is called once the listener is gone, after
  /// `Remove()`.
  static ListenerRegistrationBridge AddRealtimeSnapshotListener(
      const StageBridgeVector& stages,
      const FirestoreBridge& firestore,
      bool include_metadata_changes,
      int32_t listen_source,
      int32_t server_timestamp_behavior,
      void* context,
      ContextReleaseCallback release_context,
      PipelineSnapshotCallback callback) noexcept;

 private:
  friend struct PipelineAccess;
  std::shared_ptr<api::Pipeline> pipeline_;
};

}  // namespace swift_bridge
}  // namespace firestore
}  // namespace firebase

#endif  // PIPELINE_BRIDGE_H_
