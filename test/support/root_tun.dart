Map<String, dynamic> rootTunSnapshotJson({
  String epoch = 'boot1',
  int seq = 42,
  int revision = 8,
  String state = 'running',
  String manager = 'kernelsu',
  String auth = 'granted',
  bool enabled = true,
  bool autostart = true,
  String? error,
}) => {
  'schemaVersion': 1,
  'epoch': epoch,
  'seq': seq,
  'intentRevision': revision,
  'state': state,
  'rootManager': manager,
  'authStatus': auth,
  'mode': enabled ? 'rootTun' : 'off',
  'rootTunEnabled': enabled,
  'autostartEnabled': autostart,
  'lastErrorCode': error,
  'lastErrorAt': error == null ? null : 1792713600000,
  'warnings': <String>[],
  'authDeadlineAt': null,
  'startedAt': 1792713600000,
  'updatedAt': 1792713601000,
  'stale': false,
};

Map<String, dynamic> rootTunSuccess(Object data) => {
  'ok': true,
  'data': data,
  'error': null,
};

Map<String, dynamic> rootTunEventJson({
  String epoch = 'boot1',
  int seq = 43,
  int baseSeq = 42,
  Map<String, dynamic> changes = const {},
  Map<String, dynamic>? snapshot,
  String? code,
}) => {
  'schemaVersion': 1,
  'epoch': epoch,
  'seq': seq,
  'kind': snapshot == null ? 'delta' : 'snapshot',
  'requestId': null,
  'code': code,
  'at': 1792713602000,
  'snapshot': ?snapshot,
  if (snapshot == null) ...{'baseSeq': baseSeq, 'changes': changes},
};
