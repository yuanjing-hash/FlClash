// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of '../root_tun.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RootTunSnapshot {

@JsonKey(required: true, fromJson: _rootTunInt) int get schemaVersion;@JsonKey(required: true) String get epoch;@JsonKey(required: true, fromJson: _rootTunInt) int get seq;@JsonKey(required: true, fromJson: _rootTunInt) int get intentRevision;@JsonKey(required: true) RootTunState get state;@JsonKey(required: true) RootManager get rootManager;@JsonKey(required: true) AuthStatus get authStatus;@JsonKey(required: true) RootTunMode get mode;@JsonKey(required: true) bool get rootTunEnabled;@JsonKey(required: true) bool get autostartEnabled;@JsonKey(required: true) String? get lastErrorCode;@JsonKey(required: true, fromJson: _rootTunNullableInt) int? get lastErrorAt;@JsonKey(required: true) List<String> get warnings;@JsonKey(required: true, fromJson: _rootTunNullableInt) int? get authDeadlineAt;@JsonKey(required: true, fromJson: _rootTunNullableInt) int? get startedAt;@JsonKey(required: true, fromJson: _rootTunInt) int get updatedAt;@JsonKey(required: true) bool get stale;
/// Create a copy of RootTunSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RootTunSnapshotCopyWith<RootTunSnapshot> get copyWith => _$RootTunSnapshotCopyWithImpl<RootTunSnapshot>(this as RootTunSnapshot, _$identity);

  /// Serializes this RootTunSnapshot to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as RootTunSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RootTunSnapshot&&(identical(other.schemaVersion, _this.schemaVersion) || other.schemaVersion == _this.schemaVersion)&&(identical(other.epoch, _this.epoch) || other.epoch == _this.epoch)&&(identical(other.seq, _this.seq) || other.seq == _this.seq)&&(identical(other.intentRevision, _this.intentRevision) || other.intentRevision == _this.intentRevision)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.rootManager, _this.rootManager) || other.rootManager == _this.rootManager)&&(identical(other.authStatus, _this.authStatus) || other.authStatus == _this.authStatus)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.rootTunEnabled, _this.rootTunEnabled) || other.rootTunEnabled == _this.rootTunEnabled)&&(identical(other.autostartEnabled, _this.autostartEnabled) || other.autostartEnabled == _this.autostartEnabled)&&(identical(other.lastErrorCode, _this.lastErrorCode) || other.lastErrorCode == _this.lastErrorCode)&&(identical(other.lastErrorAt, _this.lastErrorAt) || other.lastErrorAt == _this.lastErrorAt)&&const DeepCollectionEquality().equals(other.warnings, _this.warnings)&&(identical(other.authDeadlineAt, _this.authDeadlineAt) || other.authDeadlineAt == _this.authDeadlineAt)&&(identical(other.startedAt, _this.startedAt) || other.startedAt == _this.startedAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.stale, _this.stale) || other.stale == _this.stale));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as RootTunSnapshot;
  return Object.hash(runtimeType,_this.schemaVersion,_this.epoch,_this.seq,_this.intentRevision,_this.state,_this.rootManager,_this.authStatus,_this.mode,_this.rootTunEnabled,_this.autostartEnabled,_this.lastErrorCode,_this.lastErrorAt,const DeepCollectionEquality().hash(_this.warnings),_this.authDeadlineAt,_this.startedAt,_this.updatedAt,_this.stale);
}

@override
String toString() {
  final _this = this as RootTunSnapshot;
  return 'RootTunSnapshot(schemaVersion: ${_this.schemaVersion}, epoch: ${_this.epoch}, seq: ${_this.seq}, intentRevision: ${_this.intentRevision}, state: ${_this.state}, rootManager: ${_this.rootManager}, authStatus: ${_this.authStatus}, mode: ${_this.mode}, rootTunEnabled: ${_this.rootTunEnabled}, autostartEnabled: ${_this.autostartEnabled}, lastErrorCode: ${_this.lastErrorCode}, lastErrorAt: ${_this.lastErrorAt}, warnings: ${_this.warnings}, authDeadlineAt: ${_this.authDeadlineAt}, startedAt: ${_this.startedAt}, updatedAt: ${_this.updatedAt}, stale: ${_this.stale})';
}


}

/// @nodoc
abstract mixin class $RootTunSnapshotCopyWith<$Res>  {
  factory $RootTunSnapshotCopyWith(RootTunSnapshot value, $Res Function(RootTunSnapshot) _then) = _$RootTunSnapshotCopyWithImpl;
@useResult
$Res call({
@JsonKey(required: true, fromJson: _rootTunInt) int schemaVersion,@JsonKey(required: true) String epoch,@JsonKey(required: true, fromJson: _rootTunInt) int seq,@JsonKey(required: true, fromJson: _rootTunInt) int intentRevision,@JsonKey(required: true) RootTunState state,@JsonKey(required: true) RootManager rootManager,@JsonKey(required: true) AuthStatus authStatus,@JsonKey(required: true) RootTunMode mode,@JsonKey(required: true) bool rootTunEnabled,@JsonKey(required: true) bool autostartEnabled,@JsonKey(required: true) String? lastErrorCode,@JsonKey(required: true, fromJson: _rootTunNullableInt) int? lastErrorAt,@JsonKey(required: true) List<String> warnings,@JsonKey(required: true, fromJson: _rootTunNullableInt) int? authDeadlineAt,@JsonKey(required: true, fromJson: _rootTunNullableInt) int? startedAt,@JsonKey(required: true, fromJson: _rootTunInt) int updatedAt,@JsonKey(required: true) bool stale
});




}
/// @nodoc
class _$RootTunSnapshotCopyWithImpl<$Res>
    implements $RootTunSnapshotCopyWith<$Res> {
  _$RootTunSnapshotCopyWithImpl(this._self, this._then);

  final RootTunSnapshot _self;
  final $Res Function(RootTunSnapshot) _then;

/// Create a copy of RootTunSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? schemaVersion = null,Object? epoch = null,Object? seq = null,Object? intentRevision = null,Object? state = null,Object? rootManager = null,Object? authStatus = null,Object? mode = null,Object? rootTunEnabled = null,Object? autostartEnabled = null,Object? lastErrorCode = freezed,Object? lastErrorAt = freezed,Object? warnings = null,Object? authDeadlineAt = freezed,Object? startedAt = freezed,Object? updatedAt = null,Object? stale = null,}) {
  return _then(RootTunSnapshot(
schemaVersion: null == schemaVersion ? _self.schemaVersion : schemaVersion // ignore: cast_nullable_to_non_nullable
as int,epoch: null == epoch ? _self.epoch : epoch // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,intentRevision: null == intentRevision ? _self.intentRevision : intentRevision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as RootTunState,rootManager: null == rootManager ? _self.rootManager : rootManager // ignore: cast_nullable_to_non_nullable
as RootManager,authStatus: null == authStatus ? _self.authStatus : authStatus // ignore: cast_nullable_to_non_nullable
as AuthStatus,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as RootTunMode,rootTunEnabled: null == rootTunEnabled ? _self.rootTunEnabled : rootTunEnabled // ignore: cast_nullable_to_non_nullable
as bool,autostartEnabled: null == autostartEnabled ? _self.autostartEnabled : autostartEnabled // ignore: cast_nullable_to_non_nullable
as bool,lastErrorCode: freezed == lastErrorCode ? _self.lastErrorCode : lastErrorCode // ignore: cast_nullable_to_non_nullable
as String?,lastErrorAt: freezed == lastErrorAt ? _self.lastErrorAt : lastErrorAt // ignore: cast_nullable_to_non_nullable
as int?,warnings: null == warnings ? _self.warnings : warnings // ignore: cast_nullable_to_non_nullable
as List<String>,authDeadlineAt: freezed == authDeadlineAt ? _self.authDeadlineAt : authDeadlineAt // ignore: cast_nullable_to_non_nullable
as int?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [RootTunSnapshot].
extension RootTunSnapshotPatterns on RootTunSnapshot {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RootTunSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RootTunSnapshot() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RootTunSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _RootTunSnapshot():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RootTunSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _RootTunSnapshot() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(required: true, fromJson: _rootTunInt)  int schemaVersion, @JsonKey(required: true)  String epoch, @JsonKey(required: true, fromJson: _rootTunInt)  int seq, @JsonKey(required: true, fromJson: _rootTunInt)  int intentRevision, @JsonKey(required: true)  RootTunState state, @JsonKey(required: true)  RootManager rootManager, @JsonKey(required: true)  AuthStatus authStatus, @JsonKey(required: true)  RootTunMode mode, @JsonKey(required: true)  bool rootTunEnabled, @JsonKey(required: true)  bool autostartEnabled, @JsonKey(required: true)  String? lastErrorCode, @JsonKey(required: true, fromJson: _rootTunNullableInt)  int? lastErrorAt, @JsonKey(required: true)  List<String> warnings, @JsonKey(required: true, fromJson: _rootTunNullableInt)  int? authDeadlineAt, @JsonKey(required: true, fromJson: _rootTunNullableInt)  int? startedAt, @JsonKey(required: true, fromJson: _rootTunInt)  int updatedAt, @JsonKey(required: true)  bool stale)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RootTunSnapshot() when $default != null:
return $default(_that.schemaVersion,_that.epoch,_that.seq,_that.intentRevision,_that.state,_that.rootManager,_that.authStatus,_that.mode,_that.rootTunEnabled,_that.autostartEnabled,_that.lastErrorCode,_that.lastErrorAt,_that.warnings,_that.authDeadlineAt,_that.startedAt,_that.updatedAt,_that.stale);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(required: true, fromJson: _rootTunInt)  int schemaVersion, @JsonKey(required: true)  String epoch, @JsonKey(required: true, fromJson: _rootTunInt)  int seq, @JsonKey(required: true, fromJson: _rootTunInt)  int intentRevision, @JsonKey(required: true)  RootTunState state, @JsonKey(required: true)  RootManager rootManager, @JsonKey(required: true)  AuthStatus authStatus, @JsonKey(required: true)  RootTunMode mode, @JsonKey(required: true)  bool rootTunEnabled, @JsonKey(required: true)  bool autostartEnabled, @JsonKey(required: true)  String? lastErrorCode, @JsonKey(required: true, fromJson: _rootTunNullableInt)  int? lastErrorAt, @JsonKey(required: true)  List<String> warnings, @JsonKey(required: true, fromJson: _rootTunNullableInt)  int? authDeadlineAt, @JsonKey(required: true, fromJson: _rootTunNullableInt)  int? startedAt, @JsonKey(required: true, fromJson: _rootTunInt)  int updatedAt, @JsonKey(required: true)  bool stale)  $default,) {final _that = this;
switch (_that) {
case _RootTunSnapshot():
return $default(_that.schemaVersion,_that.epoch,_that.seq,_that.intentRevision,_that.state,_that.rootManager,_that.authStatus,_that.mode,_that.rootTunEnabled,_that.autostartEnabled,_that.lastErrorCode,_that.lastErrorAt,_that.warnings,_that.authDeadlineAt,_that.startedAt,_that.updatedAt,_that.stale);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(required: true, fromJson: _rootTunInt)  int schemaVersion, @JsonKey(required: true)  String epoch, @JsonKey(required: true, fromJson: _rootTunInt)  int seq, @JsonKey(required: true, fromJson: _rootTunInt)  int intentRevision, @JsonKey(required: true)  RootTunState state, @JsonKey(required: true)  RootManager rootManager, @JsonKey(required: true)  AuthStatus authStatus, @JsonKey(required: true)  RootTunMode mode, @JsonKey(required: true)  bool rootTunEnabled, @JsonKey(required: true)  bool autostartEnabled, @JsonKey(required: true)  String? lastErrorCode, @JsonKey(required: true, fromJson: _rootTunNullableInt)  int? lastErrorAt, @JsonKey(required: true)  List<String> warnings, @JsonKey(required: true, fromJson: _rootTunNullableInt)  int? authDeadlineAt, @JsonKey(required: true, fromJson: _rootTunNullableInt)  int? startedAt, @JsonKey(required: true, fromJson: _rootTunInt)  int updatedAt, @JsonKey(required: true)  bool stale)?  $default,) {final _that = this;
switch (_that) {
case _RootTunSnapshot() when $default != null:
return $default(_that.schemaVersion,_that.epoch,_that.seq,_that.intentRevision,_that.state,_that.rootManager,_that.authStatus,_that.mode,_that.rootTunEnabled,_that.autostartEnabled,_that.lastErrorCode,_that.lastErrorAt,_that.warnings,_that.authDeadlineAt,_that.startedAt,_that.updatedAt,_that.stale);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(checked: true, explicitToJson: true)
class _RootTunSnapshot implements RootTunSnapshot {
  const _RootTunSnapshot({@JsonKey(required: true, fromJson: _rootTunInt) required this.schemaVersion, @JsonKey(required: true) required this.epoch, @JsonKey(required: true, fromJson: _rootTunInt) required this.seq, @JsonKey(required: true, fromJson: _rootTunInt) required this.intentRevision, @JsonKey(required: true) required this.state, @JsonKey(required: true) required this.rootManager, @JsonKey(required: true) required this.authStatus, @JsonKey(required: true) required this.mode, @JsonKey(required: true) required this.rootTunEnabled, @JsonKey(required: true) required this.autostartEnabled, @JsonKey(required: true) required this.lastErrorCode, @JsonKey(required: true, fromJson: _rootTunNullableInt) required this.lastErrorAt, @JsonKey(required: true) required  List<String> warnings, @JsonKey(required: true, fromJson: _rootTunNullableInt) required this.authDeadlineAt, @JsonKey(required: true, fromJson: _rootTunNullableInt) required this.startedAt, @JsonKey(required: true, fromJson: _rootTunInt) required this.updatedAt, @JsonKey(required: true) required this.stale}): _warnings = warnings;
  factory _RootTunSnapshot.fromJson(Map<String, dynamic> json) => _$RootTunSnapshotFromJson(json);

@override@JsonKey(required: true, fromJson: _rootTunInt) final  int schemaVersion;
@override@JsonKey(required: true) final  String epoch;
@override@JsonKey(required: true, fromJson: _rootTunInt) final  int seq;
@override@JsonKey(required: true, fromJson: _rootTunInt) final  int intentRevision;
@override@JsonKey(required: true) final  RootTunState state;
@override@JsonKey(required: true) final  RootManager rootManager;
@override@JsonKey(required: true) final  AuthStatus authStatus;
@override@JsonKey(required: true) final  RootTunMode mode;
@override@JsonKey(required: true) final  bool rootTunEnabled;
@override@JsonKey(required: true) final  bool autostartEnabled;
@override@JsonKey(required: true) final  String? lastErrorCode;
@override@JsonKey(required: true, fromJson: _rootTunNullableInt) final  int? lastErrorAt;
 final  List<String> _warnings;
@override@JsonKey(required: true) List<String> get warnings {
  if (_warnings is EqualUnmodifiableListView) return _warnings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_warnings);
}

@override@JsonKey(required: true, fromJson: _rootTunNullableInt) final  int? authDeadlineAt;
@override@JsonKey(required: true, fromJson: _rootTunNullableInt) final  int? startedAt;
@override@JsonKey(required: true, fromJson: _rootTunInt) final  int updatedAt;
@override@JsonKey(required: true) final  bool stale;

/// Create a copy of RootTunSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RootTunSnapshotCopyWith<_RootTunSnapshot> get copyWith => __$RootTunSnapshotCopyWithImpl<_RootTunSnapshot>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RootTunSnapshotToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RootTunSnapshot&&(identical(other.schemaVersion, schemaVersion) || other.schemaVersion == schemaVersion)&&(identical(other.epoch, epoch) || other.epoch == epoch)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.intentRevision, intentRevision) || other.intentRevision == intentRevision)&&(identical(other.state, state) || other.state == state)&&(identical(other.rootManager, rootManager) || other.rootManager == rootManager)&&(identical(other.authStatus, authStatus) || other.authStatus == authStatus)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.rootTunEnabled, rootTunEnabled) || other.rootTunEnabled == rootTunEnabled)&&(identical(other.autostartEnabled, autostartEnabled) || other.autostartEnabled == autostartEnabled)&&(identical(other.lastErrorCode, lastErrorCode) || other.lastErrorCode == lastErrorCode)&&(identical(other.lastErrorAt, lastErrorAt) || other.lastErrorAt == lastErrorAt)&&const DeepCollectionEquality().equals(other.warnings, _warnings)&&(identical(other.authDeadlineAt, authDeadlineAt) || other.authDeadlineAt == authDeadlineAt)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.stale, stale) || other.stale == stale));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,schemaVersion,epoch,seq,intentRevision,state,rootManager,authStatus,mode,rootTunEnabled,autostartEnabled,lastErrorCode,lastErrorAt,const DeepCollectionEquality().hash(_warnings),authDeadlineAt,startedAt,updatedAt,stale);
}

@override
String toString() {
    return 'RootTunSnapshot(schemaVersion: $schemaVersion, epoch: $epoch, seq: $seq, intentRevision: $intentRevision, state: $state, rootManager: $rootManager, authStatus: $authStatus, mode: $mode, rootTunEnabled: $rootTunEnabled, autostartEnabled: $autostartEnabled, lastErrorCode: $lastErrorCode, lastErrorAt: $lastErrorAt, warnings: $warnings, authDeadlineAt: $authDeadlineAt, startedAt: $startedAt, updatedAt: $updatedAt, stale: $stale)';
}


}

/// @nodoc
abstract mixin class _$RootTunSnapshotCopyWith<$Res> implements $RootTunSnapshotCopyWith<$Res> {
  factory _$RootTunSnapshotCopyWith(_RootTunSnapshot value, $Res Function(_RootTunSnapshot) _then) = __$RootTunSnapshotCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(required: true, fromJson: _rootTunInt) int schemaVersion,@JsonKey(required: true) String epoch,@JsonKey(required: true, fromJson: _rootTunInt) int seq,@JsonKey(required: true, fromJson: _rootTunInt) int intentRevision,@JsonKey(required: true) RootTunState state,@JsonKey(required: true) RootManager rootManager,@JsonKey(required: true) AuthStatus authStatus,@JsonKey(required: true) RootTunMode mode,@JsonKey(required: true) bool rootTunEnabled,@JsonKey(required: true) bool autostartEnabled,@JsonKey(required: true) String? lastErrorCode,@JsonKey(required: true, fromJson: _rootTunNullableInt) int? lastErrorAt,@JsonKey(required: true) List<String> warnings,@JsonKey(required: true, fromJson: _rootTunNullableInt) int? authDeadlineAt,@JsonKey(required: true, fromJson: _rootTunNullableInt) int? startedAt,@JsonKey(required: true, fromJson: _rootTunInt) int updatedAt,@JsonKey(required: true) bool stale
});




}
/// @nodoc
class __$RootTunSnapshotCopyWithImpl<$Res>
    implements _$RootTunSnapshotCopyWith<$Res> {
  __$RootTunSnapshotCopyWithImpl(this._self, this._then);

  final _RootTunSnapshot _self;
  final $Res Function(_RootTunSnapshot) _then;

/// Create a copy of RootTunSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? schemaVersion = null,Object? epoch = null,Object? seq = null,Object? intentRevision = null,Object? state = null,Object? rootManager = null,Object? authStatus = null,Object? mode = null,Object? rootTunEnabled = null,Object? autostartEnabled = null,Object? lastErrorCode = freezed,Object? lastErrorAt = freezed,Object? warnings = null,Object? authDeadlineAt = freezed,Object? startedAt = freezed,Object? updatedAt = null,Object? stale = null,}) {
  return _then(_RootTunSnapshot(
schemaVersion: null == schemaVersion ? _self.schemaVersion : schemaVersion // ignore: cast_nullable_to_non_nullable
as int,epoch: null == epoch ? _self.epoch : epoch // ignore: cast_nullable_to_non_nullable
as String,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,intentRevision: null == intentRevision ? _self.intentRevision : intentRevision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as RootTunState,rootManager: null == rootManager ? _self.rootManager : rootManager // ignore: cast_nullable_to_non_nullable
as RootManager,authStatus: null == authStatus ? _self.authStatus : authStatus // ignore: cast_nullable_to_non_nullable
as AuthStatus,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as RootTunMode,rootTunEnabled: null == rootTunEnabled ? _self.rootTunEnabled : rootTunEnabled // ignore: cast_nullable_to_non_nullable
as bool,autostartEnabled: null == autostartEnabled ? _self.autostartEnabled : autostartEnabled // ignore: cast_nullable_to_non_nullable
as bool,lastErrorCode: freezed == lastErrorCode ? _self.lastErrorCode : lastErrorCode // ignore: cast_nullable_to_non_nullable
as String?,lastErrorAt: freezed == lastErrorAt ? _self.lastErrorAt : lastErrorAt // ignore: cast_nullable_to_non_nullable
as int?,warnings: null == warnings ? _self._warnings : warnings // ignore: cast_nullable_to_non_nullable
as List<String>,authDeadlineAt: freezed == authDeadlineAt ? _self.authDeadlineAt : authDeadlineAt // ignore: cast_nullable_to_non_nullable
as int?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$RootTunError {

@JsonKey(required: true) String get code;@JsonKey(required: true) Map<String, dynamic> get details;@JsonKey(required: true) bool get retryable;
/// Create a copy of RootTunError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RootTunErrorCopyWith<RootTunError> get copyWith => _$RootTunErrorCopyWithImpl<RootTunError>(this as RootTunError, _$identity);

  /// Serializes this RootTunError to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as RootTunError;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RootTunError&&(identical(other.code, _this.code) || other.code == _this.code)&&const DeepCollectionEquality().equals(other.details, _this.details)&&(identical(other.retryable, _this.retryable) || other.retryable == _this.retryable));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as RootTunError;
  return Object.hash(runtimeType,_this.code,const DeepCollectionEquality().hash(_this.details),_this.retryable);
}

@override
String toString() {
  final _this = this as RootTunError;
  return 'RootTunError(code: ${_this.code}, details: ${_this.details}, retryable: ${_this.retryable})';
}


}

/// @nodoc
abstract mixin class $RootTunErrorCopyWith<$Res>  {
  factory $RootTunErrorCopyWith(RootTunError value, $Res Function(RootTunError) _then) = _$RootTunErrorCopyWithImpl;
@useResult
$Res call({
@JsonKey(required: true) String code,@JsonKey(required: true) Map<String, dynamic> details,@JsonKey(required: true) bool retryable
});




}
/// @nodoc
class _$RootTunErrorCopyWithImpl<$Res>
    implements $RootTunErrorCopyWith<$Res> {
  _$RootTunErrorCopyWithImpl(this._self, this._then);

  final RootTunError _self;
  final $Res Function(RootTunError) _then;

/// Create a copy of RootTunError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? details = null,Object? retryable = null,}) {
  return _then(RootTunError(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,details: null == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [RootTunError].
extension RootTunErrorPatterns on RootTunError {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RootTunError value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RootTunError() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RootTunError value)  $default,){
final _that = this;
switch (_that) {
case _RootTunError():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RootTunError value)?  $default,){
final _that = this;
switch (_that) {
case _RootTunError() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(required: true)  String code, @JsonKey(required: true)  Map<String, dynamic> details, @JsonKey(required: true)  bool retryable)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RootTunError() when $default != null:
return $default(_that.code,_that.details,_that.retryable);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(required: true)  String code, @JsonKey(required: true)  Map<String, dynamic> details, @JsonKey(required: true)  bool retryable)  $default,) {final _that = this;
switch (_that) {
case _RootTunError():
return $default(_that.code,_that.details,_that.retryable);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(required: true)  String code, @JsonKey(required: true)  Map<String, dynamic> details, @JsonKey(required: true)  bool retryable)?  $default,) {final _that = this;
switch (_that) {
case _RootTunError() when $default != null:
return $default(_that.code,_that.details,_that.retryable);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(checked: true, explicitToJson: true)
class _RootTunError implements RootTunError {
  const _RootTunError({@JsonKey(required: true) required this.code, @JsonKey(required: true) required  Map<String, dynamic> details, @JsonKey(required: true) required this.retryable}): _details = details;
  factory _RootTunError.fromJson(Map<String, dynamic> json) => _$RootTunErrorFromJson(json);

@override@JsonKey(required: true) final  String code;
 final  Map<String, dynamic> _details;
@override@JsonKey(required: true) Map<String, dynamic> get details {
  if (_details is EqualUnmodifiableMapView) return _details;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_details);
}

@override@JsonKey(required: true) final  bool retryable;

/// Create a copy of RootTunError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RootTunErrorCopyWith<_RootTunError> get copyWith => __$RootTunErrorCopyWithImpl<_RootTunError>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RootTunErrorToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RootTunError&&(identical(other.code, code) || other.code == code)&&const DeepCollectionEquality().equals(other.details, _details)&&(identical(other.retryable, retryable) || other.retryable == retryable));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,code,const DeepCollectionEquality().hash(_details),retryable);
}

@override
String toString() {
    return 'RootTunError(code: $code, details: $details, retryable: $retryable)';
}


}

/// @nodoc
abstract mixin class _$RootTunErrorCopyWith<$Res> implements $RootTunErrorCopyWith<$Res> {
  factory _$RootTunErrorCopyWith(_RootTunError value, $Res Function(_RootTunError) _then) = __$RootTunErrorCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(required: true) String code,@JsonKey(required: true) Map<String, dynamic> details,@JsonKey(required: true) bool retryable
});




}
/// @nodoc
class __$RootTunErrorCopyWithImpl<$Res>
    implements _$RootTunErrorCopyWith<$Res> {
  __$RootTunErrorCopyWithImpl(this._self, this._then);

  final _RootTunError _self;
  final $Res Function(_RootTunError) _then;

/// Create a copy of RootTunError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? details = null,Object? retryable = null,}) {
  return _then(_RootTunError(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,details: null == details ? _self._details : details // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$RootTunAck {

@JsonKey(required: true) String get requestId;@JsonKey(required: true, fromJson: _rootTunInt) int get intentRevision;@JsonKey(required: true) RootTunDisposition get disposition;@JsonKey(required: true) RootTunSnapshot get snapshot;
/// Create a copy of RootTunAck
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RootTunAckCopyWith<RootTunAck> get copyWith => _$RootTunAckCopyWithImpl<RootTunAck>(this as RootTunAck, _$identity);

  /// Serializes this RootTunAck to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as RootTunAck;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RootTunAck&&(identical(other.requestId, _this.requestId) || other.requestId == _this.requestId)&&(identical(other.intentRevision, _this.intentRevision) || other.intentRevision == _this.intentRevision)&&(identical(other.disposition, _this.disposition) || other.disposition == _this.disposition)&&(identical(other.snapshot, _this.snapshot) || other.snapshot == _this.snapshot));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as RootTunAck;
  return Object.hash(runtimeType,_this.requestId,_this.intentRevision,_this.disposition,_this.snapshot);
}

@override
String toString() {
  final _this = this as RootTunAck;
  return 'RootTunAck(requestId: ${_this.requestId}, intentRevision: ${_this.intentRevision}, disposition: ${_this.disposition}, snapshot: ${_this.snapshot})';
}


}

/// @nodoc
abstract mixin class $RootTunAckCopyWith<$Res>  {
  factory $RootTunAckCopyWith(RootTunAck value, $Res Function(RootTunAck) _then) = _$RootTunAckCopyWithImpl;
@useResult
$Res call({
@JsonKey(required: true) String requestId,@JsonKey(required: true, fromJson: _rootTunInt) int intentRevision,@JsonKey(required: true) RootTunDisposition disposition,@JsonKey(required: true) RootTunSnapshot snapshot
});


$RootTunSnapshotCopyWith<$Res> get snapshot;

}
/// @nodoc
class _$RootTunAckCopyWithImpl<$Res>
    implements $RootTunAckCopyWith<$Res> {
  _$RootTunAckCopyWithImpl(this._self, this._then);

  final RootTunAck _self;
  final $Res Function(RootTunAck) _then;

/// Create a copy of RootTunAck
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? requestId = null,Object? intentRevision = null,Object? disposition = null,Object? snapshot = null,}) {
  return _then(RootTunAck(
requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as String,intentRevision: null == intentRevision ? _self.intentRevision : intentRevision // ignore: cast_nullable_to_non_nullable
as int,disposition: null == disposition ? _self.disposition : disposition // ignore: cast_nullable_to_non_nullable
as RootTunDisposition,snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as RootTunSnapshot,
  ));
}
/// Create a copy of RootTunAck
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RootTunSnapshotCopyWith<$Res> get snapshot {
  
  return $RootTunSnapshotCopyWith<$Res>(_self.snapshot, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}
}


/// Adds pattern-matching-related methods to [RootTunAck].
extension RootTunAckPatterns on RootTunAck {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RootTunAck value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RootTunAck() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RootTunAck value)  $default,){
final _that = this;
switch (_that) {
case _RootTunAck():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RootTunAck value)?  $default,){
final _that = this;
switch (_that) {
case _RootTunAck() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(required: true)  String requestId, @JsonKey(required: true, fromJson: _rootTunInt)  int intentRevision, @JsonKey(required: true)  RootTunDisposition disposition, @JsonKey(required: true)  RootTunSnapshot snapshot)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RootTunAck() when $default != null:
return $default(_that.requestId,_that.intentRevision,_that.disposition,_that.snapshot);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(required: true)  String requestId, @JsonKey(required: true, fromJson: _rootTunInt)  int intentRevision, @JsonKey(required: true)  RootTunDisposition disposition, @JsonKey(required: true)  RootTunSnapshot snapshot)  $default,) {final _that = this;
switch (_that) {
case _RootTunAck():
return $default(_that.requestId,_that.intentRevision,_that.disposition,_that.snapshot);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(required: true)  String requestId, @JsonKey(required: true, fromJson: _rootTunInt)  int intentRevision, @JsonKey(required: true)  RootTunDisposition disposition, @JsonKey(required: true)  RootTunSnapshot snapshot)?  $default,) {final _that = this;
switch (_that) {
case _RootTunAck() when $default != null:
return $default(_that.requestId,_that.intentRevision,_that.disposition,_that.snapshot);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(checked: true, explicitToJson: true)
class _RootTunAck implements RootTunAck {
  const _RootTunAck({@JsonKey(required: true) required this.requestId, @JsonKey(required: true, fromJson: _rootTunInt) required this.intentRevision, @JsonKey(required: true) required this.disposition, @JsonKey(required: true) required this.snapshot});
  factory _RootTunAck.fromJson(Map<String, dynamic> json) => _$RootTunAckFromJson(json);

@override@JsonKey(required: true) final  String requestId;
@override@JsonKey(required: true, fromJson: _rootTunInt) final  int intentRevision;
@override@JsonKey(required: true) final  RootTunDisposition disposition;
@override@JsonKey(required: true) final  RootTunSnapshot snapshot;

/// Create a copy of RootTunAck
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RootTunAckCopyWith<_RootTunAck> get copyWith => __$RootTunAckCopyWithImpl<_RootTunAck>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RootTunAckToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RootTunAck&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.intentRevision, intentRevision) || other.intentRevision == intentRevision)&&(identical(other.disposition, disposition) || other.disposition == disposition)&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,requestId,intentRevision,disposition,snapshot);
}

@override
String toString() {
    return 'RootTunAck(requestId: $requestId, intentRevision: $intentRevision, disposition: $disposition, snapshot: $snapshot)';
}


}

/// @nodoc
abstract mixin class _$RootTunAckCopyWith<$Res> implements $RootTunAckCopyWith<$Res> {
  factory _$RootTunAckCopyWith(_RootTunAck value, $Res Function(_RootTunAck) _then) = __$RootTunAckCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(required: true) String requestId,@JsonKey(required: true, fromJson: _rootTunInt) int intentRevision,@JsonKey(required: true) RootTunDisposition disposition,@JsonKey(required: true) RootTunSnapshot snapshot
});


@override $RootTunSnapshotCopyWith<$Res> get snapshot;

}
/// @nodoc
class __$RootTunAckCopyWithImpl<$Res>
    implements _$RootTunAckCopyWith<$Res> {
  __$RootTunAckCopyWithImpl(this._self, this._then);

  final _RootTunAck _self;
  final $Res Function(_RootTunAck) _then;

/// Create a copy of RootTunAck
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? requestId = null,Object? intentRevision = null,Object? disposition = null,Object? snapshot = null,}) {
  return _then(_RootTunAck(
requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as String,intentRevision: null == intentRevision ? _self.intentRevision : intentRevision // ignore: cast_nullable_to_non_nullable
as int,disposition: null == disposition ? _self.disposition : disposition // ignore: cast_nullable_to_non_nullable
as RootTunDisposition,snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as RootTunSnapshot,
  ));
}

/// Create a copy of RootTunAck
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RootTunSnapshotCopyWith<$Res> get snapshot {
  
  return $RootTunSnapshotCopyWith<$Res>(_self.snapshot, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}
}


/// @nodoc
mixin _$RootTunLogEntry {

@JsonKey(required: true) String get cursor;@JsonKey(required: true, fromJson: _rootTunInt) int get at;@JsonKey(required: true) RootTunLogLevel get level;@JsonKey(required: true) String? get code;@JsonKey(required: true) String get message;
/// Create a copy of RootTunLogEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RootTunLogEntryCopyWith<RootTunLogEntry> get copyWith => _$RootTunLogEntryCopyWithImpl<RootTunLogEntry>(this as RootTunLogEntry, _$identity);

  /// Serializes this RootTunLogEntry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as RootTunLogEntry;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RootTunLogEntry&&(identical(other.cursor, _this.cursor) || other.cursor == _this.cursor)&&(identical(other.at, _this.at) || other.at == _this.at)&&(identical(other.level, _this.level) || other.level == _this.level)&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.message, _this.message) || other.message == _this.message));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as RootTunLogEntry;
  return Object.hash(runtimeType,_this.cursor,_this.at,_this.level,_this.code,_this.message);
}

@override
String toString() {
  final _this = this as RootTunLogEntry;
  return 'RootTunLogEntry(cursor: ${_this.cursor}, at: ${_this.at}, level: ${_this.level}, code: ${_this.code}, message: ${_this.message})';
}


}

/// @nodoc
abstract mixin class $RootTunLogEntryCopyWith<$Res>  {
  factory $RootTunLogEntryCopyWith(RootTunLogEntry value, $Res Function(RootTunLogEntry) _then) = _$RootTunLogEntryCopyWithImpl;
@useResult
$Res call({
@JsonKey(required: true) String cursor,@JsonKey(required: true, fromJson: _rootTunInt) int at,@JsonKey(required: true) RootTunLogLevel level,@JsonKey(required: true) String? code,@JsonKey(required: true) String message
});




}
/// @nodoc
class _$RootTunLogEntryCopyWithImpl<$Res>
    implements $RootTunLogEntryCopyWith<$Res> {
  _$RootTunLogEntryCopyWithImpl(this._self, this._then);

  final RootTunLogEntry _self;
  final $Res Function(RootTunLogEntry) _then;

/// Create a copy of RootTunLogEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? cursor = null,Object? at = null,Object? level = null,Object? code = freezed,Object? message = null,}) {
  return _then(RootTunLogEntry(
cursor: null == cursor ? _self.cursor : cursor // ignore: cast_nullable_to_non_nullable
as String,at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as int,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as RootTunLogLevel,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String?,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RootTunLogEntry].
extension RootTunLogEntryPatterns on RootTunLogEntry {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RootTunLogEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RootTunLogEntry() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RootTunLogEntry value)  $default,){
final _that = this;
switch (_that) {
case _RootTunLogEntry():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RootTunLogEntry value)?  $default,){
final _that = this;
switch (_that) {
case _RootTunLogEntry() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(required: true)  String cursor, @JsonKey(required: true, fromJson: _rootTunInt)  int at, @JsonKey(required: true)  RootTunLogLevel level, @JsonKey(required: true)  String? code, @JsonKey(required: true)  String message)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RootTunLogEntry() when $default != null:
return $default(_that.cursor,_that.at,_that.level,_that.code,_that.message);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(required: true)  String cursor, @JsonKey(required: true, fromJson: _rootTunInt)  int at, @JsonKey(required: true)  RootTunLogLevel level, @JsonKey(required: true)  String? code, @JsonKey(required: true)  String message)  $default,) {final _that = this;
switch (_that) {
case _RootTunLogEntry():
return $default(_that.cursor,_that.at,_that.level,_that.code,_that.message);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(required: true)  String cursor, @JsonKey(required: true, fromJson: _rootTunInt)  int at, @JsonKey(required: true)  RootTunLogLevel level, @JsonKey(required: true)  String? code, @JsonKey(required: true)  String message)?  $default,) {final _that = this;
switch (_that) {
case _RootTunLogEntry() when $default != null:
return $default(_that.cursor,_that.at,_that.level,_that.code,_that.message);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(checked: true, explicitToJson: true)
class _RootTunLogEntry implements RootTunLogEntry {
  const _RootTunLogEntry({@JsonKey(required: true) required this.cursor, @JsonKey(required: true, fromJson: _rootTunInt) required this.at, @JsonKey(required: true) required this.level, @JsonKey(required: true) required this.code, @JsonKey(required: true) required this.message});
  factory _RootTunLogEntry.fromJson(Map<String, dynamic> json) => _$RootTunLogEntryFromJson(json);

@override@JsonKey(required: true) final  String cursor;
@override@JsonKey(required: true, fromJson: _rootTunInt) final  int at;
@override@JsonKey(required: true) final  RootTunLogLevel level;
@override@JsonKey(required: true) final  String? code;
@override@JsonKey(required: true) final  String message;

/// Create a copy of RootTunLogEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RootTunLogEntryCopyWith<_RootTunLogEntry> get copyWith => __$RootTunLogEntryCopyWithImpl<_RootTunLogEntry>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RootTunLogEntryToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RootTunLogEntry&&(identical(other.cursor, cursor) || other.cursor == cursor)&&(identical(other.at, at) || other.at == at)&&(identical(other.level, level) || other.level == level)&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,cursor,at,level,code,message);
}

@override
String toString() {
    return 'RootTunLogEntry(cursor: $cursor, at: $at, level: $level, code: $code, message: $message)';
}


}

/// @nodoc
abstract mixin class _$RootTunLogEntryCopyWith<$Res> implements $RootTunLogEntryCopyWith<$Res> {
  factory _$RootTunLogEntryCopyWith(_RootTunLogEntry value, $Res Function(_RootTunLogEntry) _then) = __$RootTunLogEntryCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(required: true) String cursor,@JsonKey(required: true, fromJson: _rootTunInt) int at,@JsonKey(required: true) RootTunLogLevel level,@JsonKey(required: true) String? code,@JsonKey(required: true) String message
});




}
/// @nodoc
class __$RootTunLogEntryCopyWithImpl<$Res>
    implements _$RootTunLogEntryCopyWith<$Res> {
  __$RootTunLogEntryCopyWithImpl(this._self, this._then);

  final _RootTunLogEntry _self;
  final $Res Function(_RootTunLogEntry) _then;

/// Create a copy of RootTunLogEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? cursor = null,Object? at = null,Object? level = null,Object? code = freezed,Object? message = null,}) {
  return _then(_RootTunLogEntry(
cursor: null == cursor ? _self.cursor : cursor // ignore: cast_nullable_to_non_nullable
as String,at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as int,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as RootTunLogLevel,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String?,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$RootTunLogPage {

@JsonKey(required: true) String get sourcePath;@JsonKey(required: true) List<RootTunLogEntry> get entries;@JsonKey(required: true) String? get nextCursor;@JsonKey(required: true) bool get eof;
/// Create a copy of RootTunLogPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RootTunLogPageCopyWith<RootTunLogPage> get copyWith => _$RootTunLogPageCopyWithImpl<RootTunLogPage>(this as RootTunLogPage, _$identity);

  /// Serializes this RootTunLogPage to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as RootTunLogPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RootTunLogPage&&(identical(other.sourcePath, _this.sourcePath) || other.sourcePath == _this.sourcePath)&&const DeepCollectionEquality().equals(other.entries, _this.entries)&&(identical(other.nextCursor, _this.nextCursor) || other.nextCursor == _this.nextCursor)&&(identical(other.eof, _this.eof) || other.eof == _this.eof));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as RootTunLogPage;
  return Object.hash(runtimeType,_this.sourcePath,const DeepCollectionEquality().hash(_this.entries),_this.nextCursor,_this.eof);
}

@override
String toString() {
  final _this = this as RootTunLogPage;
  return 'RootTunLogPage(sourcePath: ${_this.sourcePath}, entries: ${_this.entries}, nextCursor: ${_this.nextCursor}, eof: ${_this.eof})';
}


}

/// @nodoc
abstract mixin class $RootTunLogPageCopyWith<$Res>  {
  factory $RootTunLogPageCopyWith(RootTunLogPage value, $Res Function(RootTunLogPage) _then) = _$RootTunLogPageCopyWithImpl;
@useResult
$Res call({
@JsonKey(required: true) String sourcePath,@JsonKey(required: true) List<RootTunLogEntry> entries,@JsonKey(required: true) String? nextCursor,@JsonKey(required: true) bool eof
});




}
/// @nodoc
class _$RootTunLogPageCopyWithImpl<$Res>
    implements $RootTunLogPageCopyWith<$Res> {
  _$RootTunLogPageCopyWithImpl(this._self, this._then);

  final RootTunLogPage _self;
  final $Res Function(RootTunLogPage) _then;

/// Create a copy of RootTunLogPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sourcePath = null,Object? entries = null,Object? nextCursor = freezed,Object? eof = null,}) {
  return _then(RootTunLogPage(
sourcePath: null == sourcePath ? _self.sourcePath : sourcePath // ignore: cast_nullable_to_non_nullable
as String,entries: null == entries ? _self.entries : entries // ignore: cast_nullable_to_non_nullable
as List<RootTunLogEntry>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,eof: null == eof ? _self.eof : eof // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [RootTunLogPage].
extension RootTunLogPagePatterns on RootTunLogPage {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RootTunLogPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RootTunLogPage() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RootTunLogPage value)  $default,){
final _that = this;
switch (_that) {
case _RootTunLogPage():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RootTunLogPage value)?  $default,){
final _that = this;
switch (_that) {
case _RootTunLogPage() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(required: true)  String sourcePath, @JsonKey(required: true)  List<RootTunLogEntry> entries, @JsonKey(required: true)  String? nextCursor, @JsonKey(required: true)  bool eof)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RootTunLogPage() when $default != null:
return $default(_that.sourcePath,_that.entries,_that.nextCursor,_that.eof);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(required: true)  String sourcePath, @JsonKey(required: true)  List<RootTunLogEntry> entries, @JsonKey(required: true)  String? nextCursor, @JsonKey(required: true)  bool eof)  $default,) {final _that = this;
switch (_that) {
case _RootTunLogPage():
return $default(_that.sourcePath,_that.entries,_that.nextCursor,_that.eof);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(required: true)  String sourcePath, @JsonKey(required: true)  List<RootTunLogEntry> entries, @JsonKey(required: true)  String? nextCursor, @JsonKey(required: true)  bool eof)?  $default,) {final _that = this;
switch (_that) {
case _RootTunLogPage() when $default != null:
return $default(_that.sourcePath,_that.entries,_that.nextCursor,_that.eof);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(checked: true, explicitToJson: true)
class _RootTunLogPage implements RootTunLogPage {
  const _RootTunLogPage({@JsonKey(required: true) required this.sourcePath, @JsonKey(required: true) required  List<RootTunLogEntry> entries, @JsonKey(required: true) required this.nextCursor, @JsonKey(required: true) required this.eof}): _entries = entries;
  factory _RootTunLogPage.fromJson(Map<String, dynamic> json) => _$RootTunLogPageFromJson(json);

@override@JsonKey(required: true) final  String sourcePath;
 final  List<RootTunLogEntry> _entries;
@override@JsonKey(required: true) List<RootTunLogEntry> get entries {
  if (_entries is EqualUnmodifiableListView) return _entries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_entries);
}

@override@JsonKey(required: true) final  String? nextCursor;
@override@JsonKey(required: true) final  bool eof;

/// Create a copy of RootTunLogPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RootTunLogPageCopyWith<_RootTunLogPage> get copyWith => __$RootTunLogPageCopyWithImpl<_RootTunLogPage>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RootTunLogPageToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RootTunLogPage&&(identical(other.sourcePath, sourcePath) || other.sourcePath == sourcePath)&&const DeepCollectionEquality().equals(other.entries, _entries)&&(identical(other.nextCursor, nextCursor) || other.nextCursor == nextCursor)&&(identical(other.eof, eof) || other.eof == eof));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,sourcePath,const DeepCollectionEquality().hash(_entries),nextCursor,eof);
}

@override
String toString() {
    return 'RootTunLogPage(sourcePath: $sourcePath, entries: $entries, nextCursor: $nextCursor, eof: $eof)';
}


}

/// @nodoc
abstract mixin class _$RootTunLogPageCopyWith<$Res> implements $RootTunLogPageCopyWith<$Res> {
  factory _$RootTunLogPageCopyWith(_RootTunLogPage value, $Res Function(_RootTunLogPage) _then) = __$RootTunLogPageCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(required: true) String sourcePath,@JsonKey(required: true) List<RootTunLogEntry> entries,@JsonKey(required: true) String? nextCursor,@JsonKey(required: true) bool eof
});




}
/// @nodoc
class __$RootTunLogPageCopyWithImpl<$Res>
    implements _$RootTunLogPageCopyWith<$Res> {
  __$RootTunLogPageCopyWithImpl(this._self, this._then);

  final _RootTunLogPage _self;
  final $Res Function(_RootTunLogPage) _then;

/// Create a copy of RootTunLogPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sourcePath = null,Object? entries = null,Object? nextCursor = freezed,Object? eof = null,}) {
  return _then(_RootTunLogPage(
sourcePath: null == sourcePath ? _self.sourcePath : sourcePath // ignore: cast_nullable_to_non_nullable
as String,entries: null == entries ? _self._entries : entries // ignore: cast_nullable_to_non_nullable
as List<RootTunLogEntry>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,eof: null == eof ? _self.eof : eof // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$RootTunDiagnostics {

@JsonKey(required: true) String get path;@JsonKey(required: true, fromJson: _rootTunInt) int get sizeBytes; String get mimeType;
/// Create a copy of RootTunDiagnostics
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RootTunDiagnosticsCopyWith<RootTunDiagnostics> get copyWith => _$RootTunDiagnosticsCopyWithImpl<RootTunDiagnostics>(this as RootTunDiagnostics, _$identity);

  /// Serializes this RootTunDiagnostics to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as RootTunDiagnostics;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RootTunDiagnostics&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.sizeBytes, _this.sizeBytes) || other.sizeBytes == _this.sizeBytes)&&(identical(other.mimeType, _this.mimeType) || other.mimeType == _this.mimeType));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as RootTunDiagnostics;
  return Object.hash(runtimeType,_this.path,_this.sizeBytes,_this.mimeType);
}

@override
String toString() {
  final _this = this as RootTunDiagnostics;
  return 'RootTunDiagnostics(path: ${_this.path}, sizeBytes: ${_this.sizeBytes}, mimeType: ${_this.mimeType})';
}


}

/// @nodoc
abstract mixin class $RootTunDiagnosticsCopyWith<$Res>  {
  factory $RootTunDiagnosticsCopyWith(RootTunDiagnostics value, $Res Function(RootTunDiagnostics) _then) = _$RootTunDiagnosticsCopyWithImpl;
@useResult
$Res call({
@JsonKey(required: true) String path,@JsonKey(required: true, fromJson: _rootTunInt) int sizeBytes, String mimeType
});




}
/// @nodoc
class _$RootTunDiagnosticsCopyWithImpl<$Res>
    implements $RootTunDiagnosticsCopyWith<$Res> {
  _$RootTunDiagnosticsCopyWithImpl(this._self, this._then);

  final RootTunDiagnostics _self;
  final $Res Function(RootTunDiagnostics) _then;

/// Create a copy of RootTunDiagnostics
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,Object? sizeBytes = null,Object? mimeType = null,}) {
  return _then(RootTunDiagnostics(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,sizeBytes: null == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RootTunDiagnostics].
extension RootTunDiagnosticsPatterns on RootTunDiagnostics {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RootTunDiagnostics value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RootTunDiagnostics() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RootTunDiagnostics value)  $default,){
final _that = this;
switch (_that) {
case _RootTunDiagnostics():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RootTunDiagnostics value)?  $default,){
final _that = this;
switch (_that) {
case _RootTunDiagnostics() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(required: true)  String path, @JsonKey(required: true, fromJson: _rootTunInt)  int sizeBytes,  String mimeType)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RootTunDiagnostics() when $default != null:
return $default(_that.path,_that.sizeBytes,_that.mimeType);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(required: true)  String path, @JsonKey(required: true, fromJson: _rootTunInt)  int sizeBytes,  String mimeType)  $default,) {final _that = this;
switch (_that) {
case _RootTunDiagnostics():
return $default(_that.path,_that.sizeBytes,_that.mimeType);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(required: true)  String path, @JsonKey(required: true, fromJson: _rootTunInt)  int sizeBytes,  String mimeType)?  $default,) {final _that = this;
switch (_that) {
case _RootTunDiagnostics() when $default != null:
return $default(_that.path,_that.sizeBytes,_that.mimeType);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(checked: true, explicitToJson: true)
class _RootTunDiagnostics implements RootTunDiagnostics {
  const _RootTunDiagnostics({@JsonKey(required: true) required this.path, @JsonKey(required: true, fromJson: _rootTunInt) required this.sizeBytes, this.mimeType = 'application/zip'});
  factory _RootTunDiagnostics.fromJson(Map<String, dynamic> json) => _$RootTunDiagnosticsFromJson(json);

@override@JsonKey(required: true) final  String path;
@override@JsonKey(required: true, fromJson: _rootTunInt) final  int sizeBytes;
@override@JsonKey() final  String mimeType;

/// Create a copy of RootTunDiagnostics
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RootTunDiagnosticsCopyWith<_RootTunDiagnostics> get copyWith => __$RootTunDiagnosticsCopyWithImpl<_RootTunDiagnostics>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RootTunDiagnosticsToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RootTunDiagnostics&&(identical(other.path, path) || other.path == path)&&(identical(other.sizeBytes, sizeBytes) || other.sizeBytes == sizeBytes)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,path,sizeBytes,mimeType);
}

@override
String toString() {
    return 'RootTunDiagnostics(path: $path, sizeBytes: $sizeBytes, mimeType: $mimeType)';
}


}

/// @nodoc
abstract mixin class _$RootTunDiagnosticsCopyWith<$Res> implements $RootTunDiagnosticsCopyWith<$Res> {
  factory _$RootTunDiagnosticsCopyWith(_RootTunDiagnostics value, $Res Function(_RootTunDiagnostics) _then) = __$RootTunDiagnosticsCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(required: true) String path,@JsonKey(required: true, fromJson: _rootTunInt) int sizeBytes, String mimeType
});




}
/// @nodoc
class __$RootTunDiagnosticsCopyWithImpl<$Res>
    implements _$RootTunDiagnosticsCopyWith<$Res> {
  __$RootTunDiagnosticsCopyWithImpl(this._self, this._then);

  final _RootTunDiagnostics _self;
  final $Res Function(_RootTunDiagnostics) _then;

/// Create a copy of RootTunDiagnostics
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? sizeBytes = null,Object? mimeType = null,}) {
  return _then(_RootTunDiagnostics(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,sizeBytes: null == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$RootTunViewState {

 RootTunSnapshot? get snapshot; bool? get channelAvailable; String? get lastChannelError; RootTunError? get commandError; RootTunEvent? get event; int get pendingCommands; bool get cleanupSupported; bool get autostartSupported;
/// Create a copy of RootTunViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RootTunViewStateCopyWith<RootTunViewState> get copyWith => _$RootTunViewStateCopyWithImpl<RootTunViewState>(this as RootTunViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RootTunViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RootTunViewState&&(identical(other.snapshot, _this.snapshot) || other.snapshot == _this.snapshot)&&(identical(other.channelAvailable, _this.channelAvailable) || other.channelAvailable == _this.channelAvailable)&&(identical(other.lastChannelError, _this.lastChannelError) || other.lastChannelError == _this.lastChannelError)&&(identical(other.commandError, _this.commandError) || other.commandError == _this.commandError)&&(identical(other.event, _this.event) || other.event == _this.event)&&(identical(other.pendingCommands, _this.pendingCommands) || other.pendingCommands == _this.pendingCommands)&&(identical(other.cleanupSupported, _this.cleanupSupported) || other.cleanupSupported == _this.cleanupSupported)&&(identical(other.autostartSupported, _this.autostartSupported) || other.autostartSupported == _this.autostartSupported));
}


@override
int get hashCode {
  final _this = this as RootTunViewState;
  return Object.hash(runtimeType,_this.snapshot,_this.channelAvailable,_this.lastChannelError,_this.commandError,_this.event,_this.pendingCommands,_this.cleanupSupported,_this.autostartSupported);
}

@override
String toString() {
  final _this = this as RootTunViewState;
  return 'RootTunViewState(snapshot: ${_this.snapshot}, channelAvailable: ${_this.channelAvailable}, lastChannelError: ${_this.lastChannelError}, commandError: ${_this.commandError}, event: ${_this.event}, pendingCommands: ${_this.pendingCommands}, cleanupSupported: ${_this.cleanupSupported}, autostartSupported: ${_this.autostartSupported})';
}


}

/// @nodoc
abstract mixin class $RootTunViewStateCopyWith<$Res>  {
  factory $RootTunViewStateCopyWith(RootTunViewState value, $Res Function(RootTunViewState) _then) = _$RootTunViewStateCopyWithImpl;
@useResult
$Res call({
 RootTunSnapshot? snapshot, bool? channelAvailable, String? lastChannelError, RootTunError? commandError, RootTunEvent? event, int pendingCommands, bool cleanupSupported, bool autostartSupported
});


$RootTunSnapshotCopyWith<$Res>? get snapshot;$RootTunErrorCopyWith<$Res>? get commandError;

}
/// @nodoc
class _$RootTunViewStateCopyWithImpl<$Res>
    implements $RootTunViewStateCopyWith<$Res> {
  _$RootTunViewStateCopyWithImpl(this._self, this._then);

  final RootTunViewState _self;
  final $Res Function(RootTunViewState) _then;

/// Create a copy of RootTunViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? snapshot = freezed,Object? channelAvailable = freezed,Object? lastChannelError = freezed,Object? commandError = freezed,Object? event = freezed,Object? pendingCommands = null,Object? cleanupSupported = null,Object? autostartSupported = null,}) {
  return _then(RootTunViewState(
snapshot: freezed == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as RootTunSnapshot?,channelAvailable: freezed == channelAvailable ? _self.channelAvailable : channelAvailable // ignore: cast_nullable_to_non_nullable
as bool?,lastChannelError: freezed == lastChannelError ? _self.lastChannelError : lastChannelError // ignore: cast_nullable_to_non_nullable
as String?,commandError: freezed == commandError ? _self.commandError : commandError // ignore: cast_nullable_to_non_nullable
as RootTunError?,event: freezed == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as RootTunEvent?,pendingCommands: null == pendingCommands ? _self.pendingCommands : pendingCommands // ignore: cast_nullable_to_non_nullable
as int,cleanupSupported: null == cleanupSupported ? _self.cleanupSupported : cleanupSupported // ignore: cast_nullable_to_non_nullable
as bool,autostartSupported: null == autostartSupported ? _self.autostartSupported : autostartSupported // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of RootTunViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RootTunSnapshotCopyWith<$Res>? get snapshot {
    if (_self.snapshot == null) {
    return null;
  }

  return $RootTunSnapshotCopyWith<$Res>(_self.snapshot!, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}/// Create a copy of RootTunViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RootTunErrorCopyWith<$Res>? get commandError {
    if (_self.commandError == null) {
    return null;
  }

  return $RootTunErrorCopyWith<$Res>(_self.commandError!, (value) {
    return _then(_self.copyWith(commandError: value));
  });
}
}


/// Adds pattern-matching-related methods to [RootTunViewState].
extension RootTunViewStatePatterns on RootTunViewState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RootTunViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RootTunViewState() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RootTunViewState value)  $default,){
final _that = this;
switch (_that) {
case _RootTunViewState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RootTunViewState value)?  $default,){
final _that = this;
switch (_that) {
case _RootTunViewState() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( RootTunSnapshot? snapshot,  bool? channelAvailable,  String? lastChannelError,  RootTunError? commandError,  RootTunEvent? event,  int pendingCommands,  bool cleanupSupported,  bool autostartSupported)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RootTunViewState() when $default != null:
return $default(_that.snapshot,_that.channelAvailable,_that.lastChannelError,_that.commandError,_that.event,_that.pendingCommands,_that.cleanupSupported,_that.autostartSupported);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( RootTunSnapshot? snapshot,  bool? channelAvailable,  String? lastChannelError,  RootTunError? commandError,  RootTunEvent? event,  int pendingCommands,  bool cleanupSupported,  bool autostartSupported)  $default,) {final _that = this;
switch (_that) {
case _RootTunViewState():
return $default(_that.snapshot,_that.channelAvailable,_that.lastChannelError,_that.commandError,_that.event,_that.pendingCommands,_that.cleanupSupported,_that.autostartSupported);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( RootTunSnapshot? snapshot,  bool? channelAvailable,  String? lastChannelError,  RootTunError? commandError,  RootTunEvent? event,  int pendingCommands,  bool cleanupSupported,  bool autostartSupported)?  $default,) {final _that = this;
switch (_that) {
case _RootTunViewState() when $default != null:
return $default(_that.snapshot,_that.channelAvailable,_that.lastChannelError,_that.commandError,_that.event,_that.pendingCommands,_that.cleanupSupported,_that.autostartSupported);case _:
  return null;

}
}

}

/// @nodoc


class _RootTunViewState implements RootTunViewState {
  const _RootTunViewState({this.snapshot, this.channelAvailable, this.lastChannelError, this.commandError, this.event, this.pendingCommands = 0, this.cleanupSupported = true, this.autostartSupported = true});
  

@override final  RootTunSnapshot? snapshot;
@override final  bool? channelAvailable;
@override final  String? lastChannelError;
@override final  RootTunError? commandError;
@override final  RootTunEvent? event;
@override@JsonKey() final  int pendingCommands;
@override@JsonKey() final  bool cleanupSupported;
@override@JsonKey() final  bool autostartSupported;

/// Create a copy of RootTunViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RootTunViewStateCopyWith<_RootTunViewState> get copyWith => __$RootTunViewStateCopyWithImpl<_RootTunViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RootTunViewState&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot)&&(identical(other.channelAvailable, channelAvailable) || other.channelAvailable == channelAvailable)&&(identical(other.lastChannelError, lastChannelError) || other.lastChannelError == lastChannelError)&&(identical(other.commandError, commandError) || other.commandError == commandError)&&(identical(other.event, event) || other.event == event)&&(identical(other.pendingCommands, pendingCommands) || other.pendingCommands == pendingCommands)&&(identical(other.cleanupSupported, cleanupSupported) || other.cleanupSupported == cleanupSupported)&&(identical(other.autostartSupported, autostartSupported) || other.autostartSupported == autostartSupported));
}


@override
int get hashCode {
    return Object.hash(runtimeType,snapshot,channelAvailable,lastChannelError,commandError,event,pendingCommands,cleanupSupported,autostartSupported);
}

@override
String toString() {
    return 'RootTunViewState(snapshot: $snapshot, channelAvailable: $channelAvailable, lastChannelError: $lastChannelError, commandError: $commandError, event: $event, pendingCommands: $pendingCommands, cleanupSupported: $cleanupSupported, autostartSupported: $autostartSupported)';
}


}

/// @nodoc
abstract mixin class _$RootTunViewStateCopyWith<$Res> implements $RootTunViewStateCopyWith<$Res> {
  factory _$RootTunViewStateCopyWith(_RootTunViewState value, $Res Function(_RootTunViewState) _then) = __$RootTunViewStateCopyWithImpl;
@override @useResult
$Res call({
 RootTunSnapshot? snapshot, bool? channelAvailable, String? lastChannelError, RootTunError? commandError, RootTunEvent? event, int pendingCommands, bool cleanupSupported, bool autostartSupported
});


@override $RootTunSnapshotCopyWith<$Res>? get snapshot;@override $RootTunErrorCopyWith<$Res>? get commandError;

}
/// @nodoc
class __$RootTunViewStateCopyWithImpl<$Res>
    implements _$RootTunViewStateCopyWith<$Res> {
  __$RootTunViewStateCopyWithImpl(this._self, this._then);

  final _RootTunViewState _self;
  final $Res Function(_RootTunViewState) _then;

/// Create a copy of RootTunViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? snapshot = freezed,Object? channelAvailable = freezed,Object? lastChannelError = freezed,Object? commandError = freezed,Object? event = freezed,Object? pendingCommands = null,Object? cleanupSupported = null,Object? autostartSupported = null,}) {
  return _then(_RootTunViewState(
snapshot: freezed == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as RootTunSnapshot?,channelAvailable: freezed == channelAvailable ? _self.channelAvailable : channelAvailable // ignore: cast_nullable_to_non_nullable
as bool?,lastChannelError: freezed == lastChannelError ? _self.lastChannelError : lastChannelError // ignore: cast_nullable_to_non_nullable
as String?,commandError: freezed == commandError ? _self.commandError : commandError // ignore: cast_nullable_to_non_nullable
as RootTunError?,event: freezed == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as RootTunEvent?,pendingCommands: null == pendingCommands ? _self.pendingCommands : pendingCommands // ignore: cast_nullable_to_non_nullable
as int,cleanupSupported: null == cleanupSupported ? _self.cleanupSupported : cleanupSupported // ignore: cast_nullable_to_non_nullable
as bool,autostartSupported: null == autostartSupported ? _self.autostartSupported : autostartSupported // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of RootTunViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RootTunSnapshotCopyWith<$Res>? get snapshot {
    if (_self.snapshot == null) {
    return null;
  }

  return $RootTunSnapshotCopyWith<$Res>(_self.snapshot!, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}/// Create a copy of RootTunViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RootTunErrorCopyWith<$Res>? get commandError {
    if (_self.commandError == null) {
    return null;
  }

  return $RootTunErrorCopyWith<$Res>(_self.commandError!, (value) {
    return _then(_self.copyWith(commandError: value));
  });
}
}

// dart format on
