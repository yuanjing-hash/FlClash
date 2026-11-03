import 'dart:convert';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _state = SharedState(
  stopTip: 'stop',
  startTip: 'start',
  localNetworkTip: 'local',
  currentProfileName: 'profile',
  stopText: 'stop',
  onlyStatisticsProxy: false,
  setupParams: SetupParams(
    selectedMap: {'group': 'node-a'},
    testUrl: 'https://probe.example',
  ),
);

void main() {
  test(
    'Android shared state carries the same live parameters used by the UI',
    () {
      final updates = const PatchClashConfig(
        mode: Mode.global,
        mixedPort: 7899,
      ).toUpdateParams(authentication: ['name:password'], skipCertVerify: true);
      final state = _state.copyWith(updateParams: updates);
      final payload = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
      final live = payload['updateParams'] as Map<String, dynamic>;
      expect(live['mode'], 'global');
      expect(live['mixed-port'], 7899);
      expect(live['authentication'], ['name:password']);
      expect(live['skip-cert-verify'], isTrue);
      expect(SharedState.fromJson(payload), state);
    },
  );

  test(
    'native sync observes test URL and live settings while omitting only selection comparison',
    () {
      final selected = _state.copyWith(
        setupParams: _state.setupParams!.copyWith(
          selectedMap: {'group': 'node-b'},
        ),
      );
      expect(selected.needSyncSharedState, _state.needSyncSharedState);
      final changedUrl = _state.copyWith(
        setupParams: _state.setupParams!.copyWith(
          testUrl: 'https://new.example',
        ),
      );
      expect(changedUrl.needSyncSharedState, isNot(_state.needSyncSharedState));
      final updates = const PatchClashConfig(
        mode: Mode.direct,
      ).toUpdateParams(authentication: [], skipCertVerify: false);
      expect(
        _state.copyWith(updateParams: updates).needSyncSharedState,
        isNot(_state.needSyncSharedState),
      );
    },
  );

  test('shared state saved by earlier APKs remains readable', () {
    final payload = jsonDecode(jsonEncode(_state)) as Map<String, dynamic>;
    payload.remove('updateParams');
    expect(SharedState.fromJson(payload).updateParams, isNull);
  });
}
