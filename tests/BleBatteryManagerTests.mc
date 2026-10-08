import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.Test;

(:test)
class BleManagerProbe extends BleBatteryManager {
    function initialize(di2 as Boolean, hrm as Boolean, pm as Boolean) {
        BleBatteryManager.initialize(di2, hrm, pm);
    }
    var attempts = 0;
    var lastName = "";
    var gone = false;
    var succeeds = false;
    var paired = null;
    function step(count as Number) as Void {
        for (var i = 0; i < count; i++) { computeTick(); }
    }
    (:typecheck(false))
    function scan(slot as Number, results as Array) as Void {
        onHrmPmScanResults(slot, new BleScanIterator(results));
    }
    function pair() as Void { processPendingPair(); }
    (:typecheck(false))
    function failedRead() as Void { onCharRead(null, BluetoothLowEnergy.STATUS_READ_FAIL, null); }
    (:typecheck(false))
    protected function isSignalTypeCandidate(slot as Number, result as BluetoothLowEnergy.ScanResult) as Boolean {
        return result.getCategory() == slot;
    }
    (:typecheck(false))
    protected function pairScanResult(result as BluetoothLowEnergy.ScanResult) as BluetoothLowEnergy.Device? {
        attempts++;
        lastName = result.getDeviceName();
        if (gone) { throw new BleCandidateGone(); }
        if (!succeeds) { return null; }
        paired = new BleTestDevice(lastName);
        return paired;
    }
    (:typecheck(false))
    function connection(state as BluetoothLowEnergy.ConnectionState) as Void {
        onConnectionChanged(paired, state);
    }

}

(:test)
function bleSearchesHrmBeforePmAndDi2(logger as Test.Logger) as Boolean {
    var mgr = new BleManagerProbe(true, true, true);
    Test.assertEqual(mgr.getPhaseString(), "HRM");
    mgr.stop();
    return true;
}

(:test)
function bleUsesOldSampleBudgets(logger as Test.Logger) as Boolean {
    var mgr = new BleManagerProbe(true, true, true);
    mgr.step(44);
    Test.assertEqual(mgr.getPhaseString(), "HRM");
    mgr.step(1);
    Test.assertEqual(mgr.getPhaseString(), "H>P");
    mgr.step(3);
    Test.assertEqual(mgr.getPhaseString(), "PM");
    mgr.step(45);
    Test.assertEqual(mgr.getPhaseString(), "P>D");
    mgr.step(3);
    Test.assertEqual(mgr.getPhaseString(), "DI2");
    mgr.stop();
    return true;
}

// Only native BLE advertisements and pairing are replaced. Matching, selection,
// deferred handoff, timeout transitions and failure recovery run in the manager.
(:test)
class BleScanFixture {
    var category;
    var name;
    var rssi;
    function initialize(slot as Number, label as String, strength as Number) {
        category = slot; name = label; rssi = strength;
    }
    function getCategory() as Number { return category; }
    function getDeviceName() as String { return name; }
    function getRssi() as Number { return rssi; }
}

(:test)
class BleScanIterator {
    var results as Array;
    var index as Number = 0;
    function initialize(values as Array) { results = values; }
    function next() {
        if (index >= results.size()) { return null; }
        var result = results[index];
        index++;
        return result;
    }
}

(:test)
function bleHandlesFailedReadWithoutPayload(logger as Test.Logger) as Boolean {
    var mgr = new BleManagerProbe(false, true, false);
    mgr.failedRead();
    mgr.stop();
    return true;
}

(:test)
class BleCandidateGone extends Lang.Exception {
    function initialize() {
        Exception.initialize();
        mMessage = "Candidate disappeared";
    }
}

(:test)
class BleTestDevice {
    var name;
    function initialize(label as String) { name = label; }
    function getName() as String { return name; }
    function getService(uuid) { return null; }
}

(:test)
function bleImmediatelySelectsGroupIdBeforeSignal(logger as Test.Logger) as Boolean {
    for (var slot = 1; slot <= 2; slot++) {
        var mgr = new BleManagerProbe(false, slot == 1, slot == 2);
        mgr.addCandidateId(slot, 11111);
        mgr.addCandidateId(slot, 22222);
        mgr.setLiveAntTarget(slot, 11111);
        mgr.scan(slot, [new BleScanFixture(3 - slot, "Wrong category 11111", -10),
            new BleScanFixture(slot, "Unmatched", -20),
            new BleScanFixture(slot, "Sensor 22222", -80)]);
        Test.assertEqual(mgr.getScanCandidateDebug(slot), "Sensor 22222 ID");
        Test.assertEqual(mgr.attempts, 0);
        mgr.pair();
        Test.assertEqual(mgr.attempts, 1);
        Test.assertEqual(mgr.lastName, "Sensor 22222");
        Test.assertEqual(mgr.getDevStateString(slot), "DISC");
        Test.assertEqual(mgr.getErrorMsg(), "pair:no device");
        mgr.stop();
    }
    return true;
}

(:test)
function bleImmediatelyFallsBackToStrongestService(logger as Test.Logger) as Boolean {
    for (var slot = 1; slot <= 2; slot++) {
        var mgr = new BleManagerProbe(false, slot == 1, slot == 2);
        mgr.addCandidateId(slot, 12345);
        mgr.scan(slot, [new BleScanFixture(slot, "Weak", -80),
            new BleScanFixture(3 - slot, "Other category", -10),
            new BleScanFixture(slot, "", -30)]);
        Test.assertEqual(mgr.getScanCandidateDebug(slot), "(unnamed) RSSI");
        mgr.pair();
        Test.assertEqual(mgr.attempts, 1);
        Test.assertEqual(mgr.lastName, "");
        mgr.stop();
    }
    return true;
}

(:test)
function bleRetriesDisappearedCandidateWithFreshResult(logger as Test.Logger) as Boolean {
    for (var slot = 1; slot <= 2; slot++) {
        var mgr = new BleManagerProbe(false, slot == 1, slot == 2);
        mgr.gone = true;
        mgr.scan(slot, [new BleScanFixture(slot, "Sensor 12345", -40)]);
        mgr.pair();
        Test.assertEqual(mgr.getDevStateString(slot), "DISC");
        Test.assertEqual(mgr.getErrorMsg(), "pair:Candidate disappeared");
        mgr.pair();
        Test.assertEqual(mgr.attempts, 1);
        mgr.gone = false;
        mgr.scan(slot, [new BleScanFixture(slot, "Fresh sensor", -50)]);
        mgr.pair();
        Test.assertEqual(mgr.attempts, 2);
        Test.assertEqual(mgr.lastName, "Fresh sensor");
        mgr.stop();
    }
    return true;
}

(:test)
function bleDisconnectDuringPairingAllowsAnotherAttempt(logger as Test.Logger) as Boolean {
    for (var slot = 1; slot <= 2; slot++) {
        var mgr = new BleManagerProbe(false, slot == 1, slot == 2);
        mgr.succeeds = true;
        mgr.scan(slot, [new BleScanFixture(slot, "Sensor", -40)]);
        mgr.pair();
        Test.assertEqual(mgr.getDevStateString(slot), "PAIR");
        mgr.connection(BluetoothLowEnergy.CONNECTION_STATE_DISCONNECTED);
        Test.assertEqual(mgr.getDevStateString(slot), "DISC");
        mgr.scan(slot, [new BleScanFixture(slot, "Fresh sensor", -50)]);
        mgr.pair();
        Test.assertEqual(mgr.attempts, 2);
        Test.assertEqual(mgr.lastName, "Fresh sensor");
        mgr.stop();
    }
    return true;
}

(:test)
function bleSuccessfulConnectionClearsPreviousPairError(logger as Test.Logger) as Boolean {
    var mgr = new BleManagerProbe(false, true, false);
    mgr.gone = true;
    mgr.scan(1, [new BleScanFixture(1, "Sensor", -40)]);
    mgr.pair();
    mgr.gone = false;
    mgr.succeeds = true;
    mgr.scan(1, [new BleScanFixture(1, "Sensor", -40)]);
    mgr.pair();
    mgr.connection(BluetoothLowEnergy.CONNECTION_STATE_CONNECTED);
    Test.assertEqual(mgr.getErrorMsg(), "");
    mgr.stop();
    return true;
}

(:test)
function bleActiveIdWinsWithinFreshBatch(logger as Test.Logger) as Boolean {
    for (var slot = 1; slot <= 2; slot++) {
        var mgr = new BleManagerProbe(false, slot == 1, slot == 2);
        mgr.addCandidateId(slot, 22222);
        mgr.setLiveAntTarget(slot, 11111);
        mgr.scan(slot, [new BleScanFixture(slot, "Other 22222", -20),
            new BleScanFixture(slot, "Active 11111", -80)]);
        mgr.pair();
        Test.assertEqual(mgr.lastName, "Active 11111");
        mgr.stop();
    }
    return true;
}

(:test)
function bleRefreshesPendingResultFromLatestBatch(logger as Test.Logger) as Boolean {
    for (var slot = 1; slot <= 2; slot++) {
        var mgr = new BleManagerProbe(false, slot == 1, slot == 2);
        mgr.scan(slot, [new BleScanFixture(slot, "Earlier", -20)]);
        mgr.scan(slot, [new BleScanFixture(slot, "Latest weak", -80),
            new BleScanFixture(slot, "Latest winner", -50)]);
        mgr.pair();
        Test.assertEqual(mgr.lastName, "Latest winner");
        Test.assertEqual(mgr.attempts, 1);
        mgr.stop();
    }
    return true;
}

(:test)
function bleScanStopDiscardsPendingNativeResult(logger as Test.Logger) as Boolean {
    var mgr = new BleManagerProbe(false, true, false);
    mgr.scan(1, [new BleScanFixture(1, "Sensor", -20)]);
    mgr.onScanChanged(BluetoothLowEnergy.SCAN_STATE_OFF, BluetoothLowEnergy.STATUS_SUCCESS);
    mgr.pair();
    Test.assertEqual(mgr.attempts, 0);
    mgr.stop();
    return true;
}
