import Toybox.Application.Storage;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;

class BleInnerDelegate extends BluetoothLowEnergy.BleDelegate {
    private var mOuter as BleBatteryManager;

    function initialize(outer as BleBatteryManager) {
        BleDelegate.initialize();
        mOuter = outer;
    }

    function onProfileRegister(uuid as BluetoothLowEnergy.Uuid, status as BluetoothLowEnergy.Status) as Void {
    }

    function onScanStateChange(scanState as BluetoothLowEnergy.ScanState, status as BluetoothLowEnergy.Status) as Void {
        mOuter.onScanChanged(scanState, status);
    }

    function onScanResults(scanResults as BluetoothLowEnergy.Iterator) as Void {
        mOuter.onScanResult(scanResults);
    }

    function onConnectedStateChanged(device as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        mOuter.onConnectionChanged(device, state);
    }

    function onCharacteristicRead(char as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status, value as Lang.ByteArray) as Void {
        mOuter.onCharRead(char, status, value);
    }

    function onCharacteristicChanged(char as BluetoothLowEnergy.Characteristic, value as Lang.ByteArray) as Void {
        mOuter.onCharChanged(char, value);
    }

    function onCharacteristicWrite(char as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status) as Void {
    }

    function onDescriptorRead(desc as BluetoothLowEnergy.Descriptor, status as BluetoothLowEnergy.Status, value as Lang.ByteArray) as Void {
    }

    function onDescriptorWrite(desc as BluetoothLowEnergy.Descriptor, status as BluetoothLowEnergy.Status) as Void {
    }
}

class BleBatteryManager {
    private const DEV_DI2 = 0;
    private const DEV_HRM = 1;
    private const DEV_PM = 2;
    private const DEV_COUNT = 3;

    private const PHASE_HRM = 0;
    private const PHASE_HRM_WAIT = 1;
    private const PHASE_PM = 2;
    private const PHASE_PM_WAIT = 3;
    private const PHASE_DI2 = 4;
    private const PHASE_DI2_WAIT = 5;
    private const PHASE_IDLE = 6;

    private const DI2_TIMEOUT = 45;
    private const HRM_TIMEOUT = 70;
    private const DI2_SERIAL_READ_MAX = 5;
    private const DI2_REJECTED_SCAN_MAX = 10;
    private const PM_TIMEOUT = 70;
    private const UNPAIR_WAIT = 3;
    private const PAIR_TIMEOUT = 30;
    private const MAX_RETRIES = 5;
    private const HRM_REFRESH_INTERVAL = 1200;
    private const PM_REFRESH_INTERVAL = 7200;
    private const DI2_REFRESH_INTERVAL = 7200;
    private const SCAN_WINDOW = 10;
    private const SCAN_PAUSE = 20;
    private const MAX_SCAN_BACKOFF = 120;
    private const HRM_DATA_GRACE = 5;
    private const FAILED_SCAN_RETRY = 120;
    private const FALLBACK_REFRESH_INTERVAL = 120;

    private enum {
        DS_IDLE,
        DS_PAIRING,
        DS_SUBSCRIBING,
        DS_ACTIVE,
        DS_DISCONNECTED
    }

    private enum {
        MGR_OFF,
        MGR_SCANNING,
        MGR_RUNNING,
        MGR_ERROR,
        MGR_IDLE
    }

    private var mMgrState as Number = MGR_OFF;
    private var mErrorMsg as String = "";
    private var mInner as BleInnerDelegate?;
    private var mProfileRegistered as Boolean = false;
    private var mScanDeviceCount as Number = 0;

    private var mDevState as Array<Number>;
    private var mDevBatteryPct as Array<Number>;
    private var mDevSerial as Array<String>;
    private var mRetryCount as Array<Number>;
    private var mNeedsRefresh as Array<Boolean>;
    private var mBatteryRead as Array<Boolean>;
    private var mLastRefreshTick as Array<Number>;
    private var mFailedRetryTick as Array<Number>;
    private var mFallbackBattery as Array<Boolean>;
    private var mSampleConnection as Array<Boolean>;
    private var mWant as Array<Boolean>;
    private var mDeviceName as Array<String>;
    private var mBatterySourceName as Array<String>;
    private var mStoredName as Array<String>;
    private var mDevices as Array<BluetoothLowEnergy.Device?>;
    private var mBatteryChars as Array<BluetoothLowEnergy.Characteristic?>;
    private var mSerialChars as Array<BluetoothLowEnergy.Characteristic?>;
    private var mCachedScanResult as Array<BluetoothLowEnergy.ScanResult?>;

    private var mPairingSlot as Number = -1;
    // pairDevice must run from compute(), not onScanResults (CIQQA-4261 / VM crash)
    private var mPendingPairSlot as Number = -1;
    private var mPendingPairResult as BluetoothLowEnergy.ScanResult?;
    private var mPendingPairName as String = "";
    private var mSubscribingSlot as Number = -1;
    private var mPhase as Number = 0;
    private var mTickCount as Number = 0;
    private var mPhaseStartTick as Number = 0;
    private var mDi2Needed as Boolean = true;
    private var mSubResult as String = "";
    private var mLastScanInfo as String = "";
    private var mDebugVerbose as Boolean = false;
    private var mDi2ScanName as String = "";
    private var mHrLastDataTick as Number = -100;
    private var mPmAntConnected as Boolean = false;
    private var mPairStartTick as Number = 0;
    private var mScanStartTick as Number = 0;
    private var mScanPauseUntilTick as Number = 0;
    private var mScanBackoff as Number = SCAN_PAUSE;
    private var mErrorRetryTick as Number = 0;
    private var mErrorBackoff as Number = 30;

    private var mBatterySvcUuid as BluetoothLowEnergy.Uuid?;
    private var mBatteryCharUuid as BluetoothLowEnergy.Uuid?;
    private var mDevInfoSvcUuid as BluetoothLowEnergy.Uuid?;
    private var mSerialCharUuid as BluetoothLowEnergy.Uuid?;
    private var mHrmSvcUuid as BluetoothLowEnergy.Uuid?;
    private var mShimanoBleUuid as BluetoothLowEnergy.Uuid?;
    private var mShimanoAdvUuid as BluetoothLowEnergy.Uuid?;
    private var mPmSvcUuid as BluetoothLowEnergy.Uuid?;
    private var mDi2ProbeScanResult as BluetoothLowEnergy.ScanResult?;
    private var mDi2ProbeIdMatch as Boolean = false;
    private var mDi2SerialReadAttempts as Number = 0;
    private var mDi2RejectedScans as Array<BluetoothLowEnergy.ScanResult>;

    // Keep only primitive scan-window identity; the fresh pairing result is
    // handed off separately to the next compute tick.
    private var mBestScanSeen as Boolean = false;
    private var mBestScanName as String = "";
    private var mBestScanSlot as Number = -1;
    private var mBestScanTier as Number = 0;
    private var mBestScanRssi as Number = -999;
    private var mIdentityScanWindows as Number = 0;
    private var mReacquireScanSlot as Number = -1;
    private var mReacquireScanName as String = "";
    private var mReacquireStartTick as Number = 0;

    // Per slot: Garmin can store ~3 HRMs / ~3 PMs / etc.
    // Names: one display entry per stored sensor. IDs: full + 16-bit per sensor, plus live ANT.
    private const MAX_CAND_IDS = 12;
    private const MAX_GARM_NAMES = 3;
    private const MATCH_NONE = 0;
    private const MATCH_ID = 1;
    private const MATCH_STRICT = 2;
    private var mCandIds as Array<Number>;       // flat: slot * MAX_CAND_IDS + i
    private var mCandIdCount as Array<Number>;
    private var mGarminNames as Array<String>;   // flat: slot * MAX_GARM_NAMES + i
    private var mGarminIds as Array<Number>;     // primary ANT ID per Garmin name entry
    private var mGarminNameCount as Array<Number>;
    private var mMatchBleAddr as Array<ByteArray?>; // optional MAC from SensorInfo :bleAddress
    private var mIdentityTrusted as Array<Boolean>;
    private var mBattSvcFound as Boolean = false;
    private var mBattCharFound as Boolean = false;
    private var mServiceDiscoveryResult as String = "";
    private var mSensorsScanned as Boolean = false;
    private var mRejectedDeviceNames as Array<String>;
    private var mLastScanHadRegisteredAntId as Array<Boolean>;
    private var mLiveAntTarget as Array<Number>;

    function initialize(wantDi2 as Boolean, wantHrm as Boolean, wantPm as Boolean) {
        mWant = new Array<Boolean>[DEV_COUNT];
        mWant[DEV_DI2] = wantDi2;
        mWant[DEV_HRM] = wantHrm;
        mWant[DEV_PM] = wantPm;

        mDevState = new Array<Number>[DEV_COUNT];
        mDevBatteryPct = new Array<Number>[DEV_COUNT];
        mDevSerial = new Array<String>[DEV_COUNT];
        mRetryCount = new Array<Number>[DEV_COUNT];
        mNeedsRefresh = new Array<Boolean>[DEV_COUNT];
        mBatteryRead = new Array<Boolean>[DEV_COUNT];
        mLastRefreshTick = new Array<Number>[DEV_COUNT];
        mFailedRetryTick = new Array<Number>[DEV_COUNT];
        mFallbackBattery = new Array<Boolean>[DEV_COUNT];
        mSampleConnection = new Array<Boolean>[DEV_COUNT];
        mDeviceName = new Array<String>[DEV_COUNT];
        mBatterySourceName = new Array<String>[DEV_COUNT];
        mStoredName = new Array<String>[DEV_COUNT];
        mDevices = new Array<BluetoothLowEnergy.Device?>[DEV_COUNT];
        mBatteryChars = new Array<BluetoothLowEnergy.Characteristic?>[DEV_COUNT];
        mSerialChars = new Array<BluetoothLowEnergy.Characteristic?>[DEV_COUNT];
        mCachedScanResult = new Array<BluetoothLowEnergy.ScanResult?>[DEV_COUNT];
        mCandIds = new Array<Number>[DEV_COUNT * MAX_CAND_IDS];
        mCandIdCount = new Array<Number>[DEV_COUNT];
        mGarminNames = new Array<String>[DEV_COUNT * MAX_GARM_NAMES];
        mGarminIds = new Array<Number>[DEV_COUNT * MAX_GARM_NAMES];
        mGarminNameCount = new Array<Number>[DEV_COUNT];
        mMatchBleAddr = new Array<ByteArray?>[DEV_COUNT];
        mIdentityTrusted = new Array<Boolean>[DEV_COUNT];
        mLastScanHadRegisteredAntId = new Array<Boolean>[DEV_COUNT];
        mLiveAntTarget = new Array<Number>[DEV_COUNT];

        for (var i = 0; i < DEV_COUNT * MAX_CAND_IDS; i++) {
            mCandIds[i] = 0;
        }
        // Garmin name slots: init empty strings (null elements crash on .equals)
        for (var i = 0; i < DEV_COUNT * MAX_GARM_NAMES; i++) {
            mGarminNames[i] = "";
            mGarminIds[i] = 0;
        }
        for (var i = 0; i < DEV_COUNT; i++) {
            mDevState[i] = DS_IDLE;
            mDevBatteryPct[i] = -1;
            mDevSerial[i] = "";
            mRetryCount[i] = 0;
            mNeedsRefresh[i] = true;
            mBatteryRead[i] = false;
            mLastRefreshTick[i] = 0;
            mFailedRetryTick[i] = 0;
            mFallbackBattery[i] = false;
            mSampleConnection[i] = false;
            mDeviceName[i] = "";
            mBatterySourceName[i] = "";
            mStoredName[i] = "";
            mDevices[i] = null;
            mBatteryChars[i] = null;
            mSerialChars[i] = null;
            mCachedScanResult[i] = null;
            mCandIdCount[i] = 0;
            mGarminNameCount[i] = 0;
            mMatchBleAddr[i] = null;
            mIdentityTrusted[i] = false;
            mLastScanHadRegisteredAntId[i] = false;
            mLiveAntTarget[i] = 0;
        }

        mPhase = bootPhase();
        mRejectedDeviceNames = [] as Array<String>;
        mDi2RejectedScans = [] as Array<BluetoothLowEnergy.ScanResult>;

        // Di2: prefer persisted ANT serial; ignore legacy bleDi2Addr
        loadStoredDi2Serial();
        try { Storage.deleteValue("bleDi2Addr"); } catch (exAddr) {}
        loadStoredName(DEV_DI2, "bleDi2Name");
        // Legacy PM/HRM BLE name keys — never persist those anymore
        try { Storage.deleteValue("bleHrmName"); } catch (ex0) {}
        try { Storage.deleteValue("blePmName"); } catch (ex1) {}
        var scanned = Storage.getValue("bleSensorsScanned");
        mSensorsScanned = (scanned instanceof Boolean && scanned as Boolean);
    }

    private function bootPhase() as Number {
        if (mWant[DEV_DI2]) { return PHASE_DI2; }
        return PHASE_IDLE;
    }

    private function loadStoredName(slot as Number, key as String) as Void {
        var v = Storage.getValue(key);
        if (v instanceof String) {
            mStoredName[slot] = v as String;
        }
    }

    private function slotWanted(slot as Number) as Boolean {
        if (slot == DEV_DI2) {
            return mWant[DEV_DI2] && mDi2Needed;
        }
        return mWant[slot];
    }

    private function slotCanSample(slot as Number) as Boolean {
        return slotWanted(slot) && slotConnected(slot) && mRetryCount[slot] < MAX_RETRIES && mNeedsRefresh[slot];
    }

    private function slotConnected(slot as Number) as Boolean {
        if (slot == DEV_PM) { return mPmAntConnected; }
        if (slot == DEV_HRM) {
            return mHrLastDataTick >= 0 && mTickCount - mHrLastDataTick <= HRM_DATA_GRACE;
        }
        return true;
    }

    private function sampleTimeout(slot as Number) as Number {
        if (slot == DEV_HRM) { return HRM_TIMEOUT; }
        if (slot == DEV_PM) { return PM_TIMEOUT; }
        return DI2_TIMEOUT;
    }

    private function refreshInterval(slot as Number) as Number {
        if (slot == DEV_HRM) { return HRM_REFRESH_INTERVAL; }
        if (slot == DEV_PM) { return PM_REFRESH_INTERVAL; }
        return DI2_REFRESH_INTERVAL;
    }

    private function phaseForSlot(slot as Number) as Number {
        if (slot == DEV_HRM) { return PHASE_HRM; }
        if (slot == DEV_PM) { return PHASE_PM; }
        return PHASE_DI2;
    }

    private function waitPhaseForSlot(slot as Number) as Number {
        if (slot == DEV_HRM) { return PHASE_HRM_WAIT; }
        if (slot == DEV_PM) { return PHASE_PM_WAIT; }
        return PHASE_DI2_WAIT;
    }

    function setDebugVerbose(on as Boolean) as Void {
        mDebugVerbose = on;
        if (!on) {
            mLastScanInfo = "";
            mSubResult = "";
            mServiceDiscoveryResult = "";
        }
    }

    // Activity HR includes Garmin's connected ANT+ or BLE HRM on an Edge.
    function setHrDataLive(live as Boolean) as Void {
        if (live) { mHrLastDataTick = mTickCount; }
        if (!live) {
            mLiveAntTarget[DEV_HRM] = 0;
        }
    }

    function setPmAntConnected(connected as Boolean) as Void {
        mPmAntConnected = connected;
    }

    // Prefer Garmin entry whose ANT ID matches the live activity sensor (e.g. worn HRM).
    function setLiveAntTarget(slot as Number, antId as Number) as Void {
        if (slot < 0 || slot >= DEV_COUNT) { return; }
        mLiveAntTarget[slot] = antId > 0 ? antId : 0;
    }

        // Di2: pair strongest Shimano advert, verify via Device Info serial vs ANT serial
    private function allowDi2ShimanoProbe() as Boolean {
        return slotWanted(DEV_DI2);
    }

    private function isShimanoScanResult(result as BluetoothLowEnergy.ScanResult) as Boolean {
        return hasShimanoManuf(result) || scanHasShimanoAdvUuid(result);
    }

    // Pass 3: closest RSSI only when this scan window had no registered ANT IDs in BLE names.
    private function allowSignalFallback(slot as Number) as Boolean {
        if (slot < 0 || slot >= DEV_COUNT) { return false; }
        if (slot == DEV_DI2 && mLastScanHadRegisteredAntId[slot]) { return false; }
        if (slot == DEV_HRM) {
            return slotConnected(DEV_HRM);
        }
        if (slot == DEV_PM) {
            return slotConnected(DEV_PM);
        }
        if (slot == DEV_DI2) {
            return allowDi2ShimanoProbe();
        }
        return false;
    }

    private function resetScanCandidate() as Void {
        mBestScanSeen = false;
        mBestScanName = "";
        mBestScanSlot = -1;
        mBestScanTier = MATCH_NONE;
        mBestScanRssi = -999;
    }

    private function resetReacquireCandidate() as Void {
        mReacquireScanSlot = -1;
        mReacquireScanName = "";
        mReacquireStartTick = 0;
    }

    private function considerScanCandidate(slot as Number, result as BluetoothLowEnergy.ScanResult, bleName as String) as Void {
        var matchInfo = bestEntryMatchForBleName(slot, bleName);
        var tier = matchInfo[0];
        // When Garmin exposes the active ANT ID, another *registered* sensor
        // is not an identity match for this battery sample.
        if (mLiveAntTarget[slot] > 0) {
            if (nameMatchesLiveAntTarget(slot, bleName)) {
                if (tier < MATCH_ID) { tier = MATCH_ID; }
            } else {
                tier = MATCH_NONE;
            }
        }
        var rssi = -999;
        try { rssi = result.getRssi(); } catch (exRssi) {}
        if (!mBestScanSeen || isBetterHrmPmScanMatch(slot, tier, rssi, bleName,
                mBestScanTier, mBestScanRssi, mBestScanName)) {
            mBestScanSeen = true;
            mBestScanName = bleName;
            mBestScanSlot = slot;
            mBestScanTier = tier;
            mBestScanRssi = rssi;
        }
    }

    private function nameMatchesLiveAntTarget(slot as Number, bleName as String) as Boolean {
        var target = mLiveAntTarget[slot];
        if (target <= 0 || bleName.equals("")) { return false; }
        if (nameContainsAntId(bleName, target)) { return true; }
        var target16 = target & 0xFFFF;
        return target16 > 0 && target16 != target && nameContainsAntId(bleName, target16);
    }

    private function isBetterHrmPmScanMatch(slot as Number, newTier as Number, newRssi as Number,
            newName as String, curTier as Number, curRssi as Number, curName as String) as Boolean {
        if (newTier > curTier) { return true; }
        if (newTier < curTier) { return false; }
        if (mLiveAntTarget[slot] > 0) {
            var newLive = nameMatchesLiveAntTarget(slot, newName);
            var curLive = nameMatchesLiveAntTarget(slot, curName);
            if (newLive && !curLive) { return true; }
            if (!newLive && curLive) { return false; }
        }
        return newRssi > curRssi;
    }

    private function finishScanCandidate() as Void {
        mIdentityScanWindows = 0;
        if (!mBestScanSeen || mBestScanSlot < 0) {
            resetScanCandidate();
            return;
        }
        if (mBestScanTier == MATCH_NONE && !allowSignalFallback(mBestScanSlot)) {
            resetScanCandidate();
            return;
        }
        mReacquireScanSlot = mBestScanSlot;
        mReacquireScanName = mBestScanName;
        mReacquireStartTick = 0;
        resetScanCandidate();
    }

    private function garminEntryIdMatchesBle(slot as Number, entryIdx as Number, bleName as String) as Boolean {
        if (bleName.equals("") || entryIdx < 0 || entryIdx >= mGarminNameCount[slot]) {
            return false;
        }
        var base = slot * MAX_GARM_NAMES;
        var gid = mGarminIds[base + entryIdx];
        if (gid > 0 && nameContainsAntId(bleName, gid)) {
            return true;
        }
        var g16 = gid & 0xFFFF;
        if (g16 > 0 && g16 != gid && nameContainsAntId(bleName, g16)) {
            return true;
        }
        return false;
    }

    private function garminEntryMatchesBleStrict(slot as Number, entryIdx as Number, bleName as String?) as Boolean {
        if (bleName == null || bleName.equals("") || entryIdx < 0 || entryIdx >= mGarminNameCount[slot]) {
            return false;
        }
        var base = slot * MAX_GARM_NAMES;
        var gName = mGarminNames[base + entryIdx];
        if (gName.equals("") || !bleName.equals(gName)) {
            return false;
        }
        return garminEntryIdMatchesBle(slot, entryIdx, bleName);
    }

    private function bleNameMatchesAnyGarminEntryIdOnly(slot as Number, bleName as String?) as Boolean {
        if (bleName == null || bleName.equals("")) { return false; }
        for (var i = 0; i < mGarminNameCount[slot]; i++) {
            if (garminEntryIdMatchesBle(slot, i, bleName)) {
                return true;
            }
        }
        return false;
    }

    private function bleNameMatchesAnyGarminEntryStrict(slot as Number, bleName as String?) as Boolean {
        if (bleName == null || bleName.equals("")) { return false; }
        for (var i = 0; i < mGarminNameCount[slot]; i++) {
            if (garminEntryMatchesBleStrict(slot, i, bleName)) {
                return true;
            }
        }
        return false;
    }

    private function bleNameContainsAnyRegisteredGarminAntId(slot as Number, bleName as String?) as Boolean {
        if (bleName == null || bleName.equals("")) { return false; }
        if (bleNameMatchesAnyGarminEntryIdOnly(slot, bleName)) {
            return true;
        }
        if (nameMatchesAnyAntId(slot, bleName)) {
            return true;
        }
        return false;
    }

    private function entryMatchesLiveAntTarget(slot as Number, entryIdx as Number) as Boolean {
        if (mLiveAntTarget[slot] <= 0 || entryIdx < 0 || entryIdx >= mGarminNameCount[slot]) {
            return false;
        }
        var base = slot * MAX_GARM_NAMES;
        var gid = mGarminIds[base + entryIdx];
        if (gid <= 0) { return false; }
        if (gid == mLiveAntTarget[slot]) { return true; }
        var g16 = gid & 0xFFFF;
        var live16 = mLiveAntTarget[slot] & 0xFFFF;
        return g16 > 0 && g16 == live16;
    }

    private function isBetterScanMatch(slot as Number, newTier as Number, newRssi as Number, newEntry as Number,
            curTier as Number, curRssi as Number, curEntry as Number) as Boolean {
        if (newTier > curTier) { return true; }
        if (newTier < curTier) { return false; }
        if (mLiveAntTarget[slot] > 0) {
            var newLive = entryMatchesLiveAntTarget(slot, newEntry);
            var curLive = entryMatchesLiveAntTarget(slot, curEntry);
            if (newLive && !curLive) { return true; }
            if (!newLive && curLive) { return false; }
        }
        return newRssi > curRssi;
    }

    private function bestEntryMatchForBleName(slot as Number, bleName as String?) as Array<Number> {
        var tier = MATCH_NONE;
        var entry = -1;
        if (bleName == null || bleName.equals("")) {
            return [tier, entry] as Array<Number>;
        }
        for (var i = 0; i < mGarminNameCount[slot]; i++) {
            if (garminEntryMatchesBleStrict(slot, i, bleName)) {
                if (tier < MATCH_STRICT) {
                    tier = MATCH_STRICT;
                    entry = i;
                }
            } else if (tier < MATCH_ID && garminEntryIdMatchesBle(slot, i, bleName)) {
                tier = MATCH_ID;
                entry = i;
            }
        }
        if (tier < MATCH_ID && slot == DEV_DI2 && nameMatchesAnyAntId(DEV_DI2, bleName)) {
            tier = MATCH_ID;
            entry = -1;
        }
        if (tier < MATCH_ID && (slot == DEV_HRM || slot == DEV_PM) && nameMatchesAnyAntId(slot, bleName)) {
            tier = MATCH_ID;
            entry = -1;
        }
        return [tier, entry] as Array<Number>;
    }

    private function isSignalTypeCandidate(slot as Number, result as BluetoothLowEnergy.ScanResult) as Boolean {
        if (slot == DEV_DI2) {
            return allowDi2ShimanoProbe() && isShimanoScanResult(result);
        }
        var flags = scanUuidFlags(result);
        if (slot == DEV_HRM) {
            return flags[DEV_HRM];
        }
        if (slot == DEV_PM) {
            return flags[DEV_PM];
        }
        return false;
    }

    private function scanBleNameFromResult(result as BluetoothLowEnergy.ScanResult) as String {
        try {
            var dn = result.getDeviceName();
            if (dn != null && !dn.equals("")) {
                return dn;
            }
        } catch (ex) {}
        return "";
    }

    // True when an active wanted slot still needs ANT/registered identity refresh
    function needsIdentityRefresh() as Boolean {
        for (var i = 0; i < DEV_COUNT; i++) {
            if (!slotWanted(i)) { continue; }
            if (mIdentityTrusted[i]) { continue; }
            if (needsDevice(i)) { return true; }
        }
        return false;
    }

    function start() as Void {
        try {
            mBatterySvcUuid = BluetoothLowEnergy.stringToUuid("0000180f-0000-1000-8000-00805f9b34fb");
            mBatteryCharUuid = BluetoothLowEnergy.stringToUuid("00002a19-0000-1000-8000-00805f9b34fb");
            mDevInfoSvcUuid = BluetoothLowEnergy.stringToUuid("0000180a-0000-1000-8000-00805f9b34fb");
            mSerialCharUuid = BluetoothLowEnergy.stringToUuid("00002a25-0000-1000-8000-00805f9b34fb");
            mHrmSvcUuid = BluetoothLowEnergy.stringToUuid("0000180d-0000-1000-8000-00805f9b34fb");
            mShimanoBleUuid = BluetoothLowEnergy.stringToUuid("000018ef-5348-494d-414e-4f5f424c4500");
            mShimanoAdvUuid = BluetoothLowEnergy.stringToUuid("000018ff-5348-494d-414e-4f5f424c4500");
            mPmSvcUuid = BluetoothLowEnergy.stringToUuid("00001818-0000-1000-8000-00805f9b34fb");

            mInner = new BleInnerDelegate(self);
            registerProfile();
        } catch (ex) {
            mMgrState = MGR_ERROR;
            mErrorMsg = "init:" + ex.getErrorMessage();
        }
    }

    function stop() as Void {
        try {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        } catch (ex) {}
        for (var i = 0; i < DEV_COUNT; i++) {
            if (mDevices[i] != null) {
                try { BluetoothLowEnergy.unpairDevice(mDevices[i]); } catch (ex) {}
            }
            mDevices[i] = null;
            mBatteryChars[i] = null;
            mSerialChars[i] = null;
            mCachedScanResult[i] = null;
        }
        mMgrState = MGR_OFF;
        mProfileRegistered = false;
        mPendingPairSlot = -1;
        mPendingPairResult = null;
        mPendingPairName = "";
        resetScanCandidate();
        resetReacquireCandidate();
        mIdentityScanWindows = 0;
        mDi2ProbeScanResult = null;
        mDi2ProbeIdMatch = false;
        mDi2SerialReadAttempts = 0;
        mRejectedDeviceNames = [] as Array<String>;
        mDi2RejectedScans = [] as Array<BluetoothLowEnergy.ScanResult>;
    }

    function compute() as Void {
        if (mMgrState == MGR_OFF) { return; }
        try {
            computeTick();
        } catch (ex) {
            mErrorMsg = "cmp:" + ex.getErrorMessage();
            try { BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF); } catch (ex2) {}
            mMgrState = MGR_ERROR;
        }
    }

    private function computeTick() as Void {
        mTickCount++;
        syncCategoryConnections();
        processPendingPair();

        if (mPhase == PHASE_IDLE && mMgrState == MGR_ERROR) {
            mMgrState = MGR_IDLE;
        }

        if (mMgrState == MGR_ERROR && mProfileRegistered) {
            if (mTickCount >= mErrorRetryTick) {
                mErrorRetryTick = mTickCount + mErrorBackoff;
                mErrorBackoff = nextBackoff(mErrorBackoff);
                startScanning();
            }
            return;
        }

        if (mPhase == PHASE_IDLE) {
            computeIdle();
            return;
        }

        if (mMgrState == MGR_SCANNING) {
            var scanStart = mReacquireScanSlot >= 0 && mReacquireStartTick > 0
                ? mReacquireStartTick : mScanStartTick;
            if (mTickCount - scanStart >= SCAN_WINDOW) {
                var slot = activeSlot();
                if ((slot == DEV_HRM || slot == DEV_PM) && mReacquireScanSlot < 0) {
                    if (mIdentityScanWindows == 0 && mBestScanTier < MATCH_ID) {
                        // Give a connected Garmin sensor a second window to advertise its ANT ID.
                        mIdentityScanWindows = 1;
                        stopScanning();
                        mScanPauseUntilTick = mTickCount + SCAN_PAUSE;
                        return;
                    }
                    finishScanCandidate();
                    stopScanning();
                    if (mReacquireScanSlot >= 0) {
                        // A fresh scan callback is required before pairDevice().
                        mScanPauseUntilTick = mTickCount;
                        return;
                    }
                } else if ((slot == DEV_HRM || slot == DEV_PM) && mReacquireScanSlot >= 0) {
                    // One extra window is enough to reacquire a live ScanResult.
                    resetReacquireCandidate();
                }
                stopScanning();
                mScanPauseUntilTick = mTickCount + mScanBackoff;
                mScanBackoff = nextBackoff(mScanBackoff);
                return;
            }
        }

        var elapsed = mTickCount - mPhaseStartTick;

        if (mPhase == PHASE_HRM) {
            computeHrmPhase(elapsed);
        } else if (mPhase == PHASE_HRM_WAIT) {
            if (elapsed >= UNPAIR_WAIT) {
                if (slotCanSample(DEV_PM)) {
                    beginSamplePhase(DEV_PM);
                } else if (slotCanSample(DEV_DI2)) {
                    beginSamplePhase(DEV_DI2);
                } else {
                    enterIdleIfDone();
                }
            }
        } else if (mPhase == PHASE_PM) {
            computeBriefPhase(DEV_PM, elapsed);
        } else if (mPhase == PHASE_PM_WAIT) {
            if (elapsed >= UNPAIR_WAIT) {
                if (slotCanSample(DEV_DI2)) {
                    beginSamplePhase(DEV_DI2);
                } else {
                    enterIdleIfDone();
                }
            }
        } else if (mPhase == PHASE_DI2) {
            computeBriefPhase(DEV_DI2, elapsed);
        } else if (mPhase == PHASE_DI2_WAIT) {
            if (elapsed >= UNPAIR_WAIT) {
                enterIdleIfDone();
            }
        }
    }

    private function nextBackoff(current as Number) as Number {
        var next = current * 2;
        if (next > MAX_SCAN_BACKOFF) { return MAX_SCAN_BACKOFF; }
        return next;
    }

    private function syncCategoryConnections() as Void {
        for (var slot = DEV_HRM; slot <= DEV_PM; slot++) {
            var connected = slotConnected(slot);
            if (connected == mSampleConnection[slot]) { continue; }
            mSampleConnection[slot] = connected;
            mRetryCount[slot] = 0;
            mNeedsRefresh[slot] = true;
            mLastRefreshTick[slot] = 0;
            mFailedRetryTick[slot] = 0;
            mDevBatteryPct[slot] = -1;
            mBatterySourceName[slot] = "";
            mDeviceName[slot] = "";
            mFallbackBattery[slot] = false;
            if (!connected && activeSlot() == slot) {
                stopScanning();
                forceDisconnectSlot(slot);
                mPhase = waitPhaseForSlot(slot);
                mPhaseStartTick = mTickCount;
            }
        }
    }

    private function handlePairTimeout(slot as Number, label as String) as Void {
        if (mDevState[slot] != DS_PAIRING) { return; }
        if (mTickCount - mPairStartTick < PAIR_TIMEOUT) { return; }
        mPairingSlot = -1;
        mDevState[slot] = DS_DISCONNECTED;
        mIdentityTrusted[slot] = false;
        mErrorMsg = label;
    }

    private function ensureConnecting(slot as Number) as Void {
        if (mDevState[slot] == DS_DISCONNECTED || mDevState[slot] == DS_IDLE) {
            if ((slot == DEV_HRM || slot == DEV_PM || slot == DEV_DI2) && tryPairedDeviceForSlot(slot)) {
                return;
            }
            if (!tryReconnectCached(slot)) {
                requestScan();
            }
        }
    }

    private function tryPairedDeviceForSlot(slot as Number) as Boolean {
        if (slot == DEV_DI2) {
            return tryPairedDi2Device();
        }
        if (slot != DEV_HRM && slot != DEV_PM) { return false; }
        try {
            var paired = BluetoothLowEnergy.getPairedDevices();
            var dev = paired.next();
            while (dev != null) {
                try {
                    var device = dev as BluetoothLowEnergy.Device;
                    var svc = slot == DEV_HRM ? null : mPmSvcUuid;
                    var battSvc = null;
                    var typed = null;
                    try { battSvc = device.getService(mBatterySvcUuid); } catch (exSvc) {}
                    try { typed = svc != null ? device.getService(svc) : null; } catch (exSvc2) {}
                    if (battSvc == null && typed == null) {
                        dev = paired.next();
                        continue;
                    }
                    if (slot == DEV_HRM) {
                        try {
                            var n = device.getName();
                            if (pairedDeviceStrictMatch(DEV_HRM, n)) {
                                if (tryClaimPaired(DEV_HRM, device, null)) {
                                    return true;
                                }
                            }
                        } catch (ex) {}
                    } else if (tryClaimPaired(DEV_PM, device, mPmSvcUuid)) {
                        return true;
                    }
                } catch (exDev) {}
                dev = paired.next();
            }
        } catch (ex) {}
        return false;
    }

    private function tryPairedDi2Device() as Boolean {
        // Di2 reclaim uses stored MAC + live scan — avoid claiming unknown paired BLE devices
        return false;
    }

    private function beginSamplePhase(slot as Number) as Void {
        if ((slot == DEV_HRM || slot == DEV_PM) && mRetryCount[slot] == 0) {
            mScanPauseUntilTick = mTickCount;
            mScanBackoff = SCAN_PAUSE;
        }
        mPhase = phaseForSlot(slot);
        mPhaseStartTick = mTickCount;
        mBatteryRead[slot] = false;
        if ((slot == DEV_HRM || slot == DEV_PM || slot == DEV_DI2) && tryPairedDeviceForSlot(slot)) {
            return;
        }
        if (!tryReconnectCached(slot)) { requestScan(); }
    }

    private function computeBriefPhase(slot as Number, elapsed as Number) as Void {
        if (slot == DEV_PM && !mWant[DEV_PM]) {
            mPhase = PHASE_PM_WAIT;
            mPhaseStartTick = mTickCount;
            return;
        }

        handlePairTimeout(slot, slot == DEV_PM ? "pm pair timeout" : "di2 pair timeout");
        ensureConnecting(slot);

        if (mBatteryRead[slot] || elapsed >= sampleTimeout(slot)) {
            if (!mBatteryRead[slot]) {
                mRetryCount[slot]++;
                if (slot == DEV_PM && mRetryCount[slot] >= MAX_RETRIES) {
                    mFailedRetryTick[slot] = mTickCount + FAILED_SCAN_RETRY;
                }
            }
            else { mLastRefreshTick[slot] = mTickCount; }
            if (!mBatteryRead[slot] && mRetryCount[slot] >= MAX_RETRIES) {
                clearCachedScanResult(slot);
            }
            forceDisconnectSlot(slot);
            mPhase = waitPhaseForSlot(slot);
            mPhaseStartTick = mTickCount;
        }
    }

    private function computeHrmPhase(elapsed as Number) as Void {
        if (!mWant[DEV_HRM]) {
            if (slotCanSample(DEV_PM)) {
                beginSamplePhase(DEV_PM);
            } else if (slotCanSample(DEV_DI2)) {
                beginSamplePhase(DEV_DI2);
            } else {
                enterIdleIfDone();
            }
            return;
        }

        handlePairTimeout(DEV_HRM, "pair timeout");
        ensureConnecting(DEV_HRM);

        if (mBatteryRead[DEV_HRM] || elapsed >= HRM_TIMEOUT) {
            if (!mBatteryRead[DEV_HRM]) {
                mRetryCount[DEV_HRM]++;
                if (mRetryCount[DEV_HRM] >= MAX_RETRIES) {
                    mFailedRetryTick[DEV_HRM] = mTickCount + FAILED_SCAN_RETRY;
                }
            } else {
                mRetryCount[DEV_HRM] = 0;
                mNeedsRefresh[DEV_HRM] = false;
            }
            mLastRefreshTick[DEV_HRM] = mTickCount;
            if (!mBatteryRead[DEV_HRM] && mRetryCount[DEV_HRM] >= MAX_RETRIES) {
                clearCachedScanResult(DEV_HRM);
            }
            forceDisconnectSlot(DEV_HRM);
            mPhase = PHASE_HRM_WAIT;
            mPhaseStartTick = mTickCount;
        }
    }

    private function needsRefresh(slot as Number) as Boolean {
        if (!slotWanted(slot) || !slotConnected(slot)) { return false; }
        if ((slot == DEV_HRM || slot == DEV_PM) && mRetryCount[slot] >= MAX_RETRIES) {
            return mFailedRetryTick[slot] > 0 && mTickCount >= mFailedRetryTick[slot];
        }
        if (mLastRefreshTick[slot] == 0) { return true; }
        var interval = ((slot == DEV_HRM || slot == DEV_PM) && mFallbackBattery[slot])
            ? FALLBACK_REFRESH_INTERVAL : refreshInterval(slot);
        return (mTickCount - mLastRefreshTick[slot]) >= interval;
    }

    private function computeIdle() as Void {
        if (needsRefresh(DEV_PM) || needsRefresh(DEV_DI2)) {
            if (needsRefresh(DEV_PM)) {
                mNeedsRefresh[DEV_PM] = true;
                mRetryCount[DEV_PM] = 0;
                mScanBackoff = SCAN_PAUSE;
                beginSamplePhase(DEV_PM);
            } else {
                mNeedsRefresh[DEV_DI2] = true;
                mRetryCount[DEV_DI2] = 0;
                mScanBackoff = SCAN_PAUSE;
                beginSamplePhase(DEV_DI2);
            }
            return;
        }

        if (needsRefresh(DEV_HRM)) {
            mNeedsRefresh[DEV_HRM] = true;
            mRetryCount[DEV_HRM] = 0;
            mScanBackoff = SCAN_PAUSE;
            beginSamplePhase(DEV_HRM);
        }
    }

    private function sampleDone(slot as Number) as Boolean {
        return !slotWanted(slot) || !slotConnected(slot) || mBatteryRead[slot] ||
            mRetryCount[slot] >= MAX_RETRIES || !mNeedsRefresh[slot];
    }

    private function enterIdleIfDone() as Void {
        if (mWant[DEV_PM] && !sampleDone(DEV_PM)) {
            beginSamplePhase(DEV_PM);
            return;
        }
        if (slotWanted(DEV_DI2) && !sampleDone(DEV_DI2)) {
            beginSamplePhase(DEV_DI2);
            return;
        }

        if (mWant[DEV_HRM] && !sampleDone(DEV_HRM)) {
            beginSamplePhase(DEV_HRM);
            return;
        }

        goIdle();
    }

    private function goIdle() as Void {
        mPhase = PHASE_IDLE;
        mPhaseStartTick = mTickCount;
        mMgrState = MGR_IDLE;
        stopScanning();
    }

    private function requestScan() as Void {
        if (mMgrState == MGR_SCANNING) { return; }
        if (mTickCount < mScanPauseUntilTick) { return; }
        startScanning();
    }

    private function stopScanning() as Void {
        if (mMgrState == MGR_SCANNING) {
            try { BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF); } catch (ex) {}
            mMgrState = MGR_RUNNING;
        }
    }

    function setDi2NotNeeded() as Void {
        if (!mDi2Needed) { return; }
        mDi2Needed = false;
        if (mPhase == PHASE_DI2 && (mWant[DEV_HRM] || mWant[DEV_PM])) {
            forceDisconnectSlot(DEV_DI2);
            mPhase = PHASE_DI2_WAIT;
            mPhaseStartTick = mTickCount;
        }
    }

    private function forceDisconnectSlot(slot as Number) as Void {
        if (mDevices[slot] != null) {
            try { BluetoothLowEnergy.unpairDevice(mDevices[slot]); } catch (ex) {}
        }
        mDevices[slot] = null;
        mBatteryChars[slot] = null;
        mSerialChars[slot] = null;
        mDevState[slot] = DS_DISCONNECTED;
        mIdentityTrusted[slot] = false;
        if (mPairingSlot == slot) {
            mPairingSlot = -1;
        }
        if (mPendingPairSlot == slot) {
            mPendingPairSlot = -1;
            mPendingPairResult = null;
            mPendingPairName = "";
        }
        if (slot == DEV_HRM || slot == DEV_PM) {
            if (mBestScanSlot == slot) { resetScanCandidate(); }
            if (mReacquireScanSlot == slot) { resetReacquireCandidate(); }
            mIdentityScanWindows = 0;
        }
        try { BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF); } catch (ex) {}
    }

    private function activeSlot() as Number {
        if (mPhase == PHASE_HRM) { return DEV_HRM; }
        if (mPhase == PHASE_PM) { return DEV_PM; }
        if (mPhase == PHASE_DI2) { return DEV_DI2; }
        return -1;
    }

    private function registerProfile() as Void {
        try {
            BluetoothLowEnergy.registerProfile({
                :uuid => mBatterySvcUuid,
                :characteristics => [{ :uuid => mBatteryCharUuid }]
            });
        } catch (ex) {}

        try {
            BluetoothLowEnergy.registerProfile({
                :uuid => mDevInfoSvcUuid,
                :characteristics => [{ :uuid => mSerialCharUuid }]
            });
        } catch (ex) {}

        mProfileRegistered = true;
        BluetoothLowEnergy.setDelegate(mInner);
        if (mPhase == PHASE_IDLE) {
            mMgrState = MGR_IDLE;
            return;
        }
        if (!tryPairedDevices()) {
            var slot = activeSlot();
            if (slot < 0 || !tryReconnectCached(slot)) {
                startScanning();
            }
        }
    }

    // HRM: id/name match while HR is live; PM: id in name or signal fallback.
    // Di2: ANT id / MAC / stored name rules only.
    private function pairedDeviceStrictMatch(slot as Number, name as String?) as Boolean {
        if (name == null || name.equals("")) { return false; }
        if (bleNameMatchesAnyGarminEntryStrict(slot, name)) {
            return true;
        }
        if (bleNameMatchesAnyGarminEntryIdOnly(slot, name)) {
            return true;
        }
        if (nameMatchesAnyAntId(slot, name)) {
            return true;
        }
        return false;
    }

    private function pairedDeviceAcceptable(slot as Number, device as BluetoothLowEnergy.Device) as Boolean {
        try {
            var n = device.getName();
            if (slot == DEV_HRM || slot == DEV_PM) {
                if (mLiveAntTarget[slot] > 0 && !nameMatchesLiveAntTarget(slot, n)) {
                    return false;
                }
                return pairedDeviceStrictMatch(slot, n);
            }
            if (slot == DEV_DI2) {
                return false;
            }
            return matchesSlotIdentity(slot, n);
        } catch (ex) {
            return false;
        }
    }

    private function tryClaimPaired(slot as Number, device as BluetoothLowEnergy.Device, typeSvc as BluetoothLowEnergy.Uuid?) as Boolean {
        if (!mWant[slot] || !needsDevice(slot)) { return false; }
        var battSvc = null;
        var typed = null;
        try { battSvc = device.getService(mBatterySvcUuid); } catch (ex) {}
        try { typed = typeSvc != null ? device.getService(typeSvc) : null; } catch (ex2) {}
        if (battSvc == null && typed == null) { return false; }
        if (!pairedDeviceAcceptable(slot, device)) { return false; }
        try {
            var n = device.getName();
            mDeviceName[slot] = n != null ? n : "(paired)";
        } catch (ex) {
            mDeviceName[slot] = "(paired)";
        }
        if (mPairingSlot == slot) {
            mPairingSlot = -1;
        }
        mDevices[slot] = device;
        mDevState[slot] = DS_SUBSCRIBING;
        markIdentityTrusted(slot);
        subscribeToServices(device, slot);
        return true;
    }

    private function tryPairedDevices() as Boolean {
        try {
            var paired = BluetoothLowEnergy.getPairedDevices();
            var dev = paired.next();
            while (dev != null) {
                try {
                    var device = dev as BluetoothLowEnergy.Device;
                    var target = activeSlot();
                    if (target == DEV_HRM && tryClaimPaired(DEV_HRM, device, null)) {
                        return true;
                    }
                    if (target == DEV_PM && tryClaimPaired(DEV_PM, device, mPmSvcUuid)) {
                        return true;
                    }
                    if (target == DEV_DI2 && tryClaimPaired(DEV_DI2, device, mShimanoBleUuid)) {
                        return true;
                    }
                    if (target == DEV_DI2 && tryClaimPaired(DEV_DI2, device, null)) {
                        return true;
                    }
                } catch (exDev) {}
                dev = paired.next();
            }
        } catch (ex) {
            mErrorMsg = "paired:" + ex.getErrorMessage();
        }
        return false;
    }

    private function startScanning() as Void {
        if (!mProfileRegistered || mInner == null) { return; }
        var slot = activeSlot();
        if (slot < 0 || !slotConnected(slot)) { return; }
        try {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
            mMgrState = MGR_SCANNING;
            mScanStartTick = mTickCount;
            if (mReacquireScanSlot >= 0) {
                mReacquireStartTick = mTickCount;
            } else if (mIdentityScanWindows == 0) {
                resetScanCandidate();
            }
            mPendingPairName = "";
            mScanDeviceCount = 0;
            mErrorBackoff = 30;
        } catch (ex) {
            mMgrState = MGR_ERROR;
            mErrorMsg = "scan:" + ex.getErrorMessage();
            mErrorRetryTick = mTickCount + mErrorBackoff;
        }
    }

    private function tryReconnectCached(slot as Number) as Boolean {
        // Stale ScanResult + pairDevice can hard-crash — only defer from live scan callback
        return false;
    }

    private function processPendingPair() as Void {
        if (mPendingPairSlot < 0 || mPendingPairResult == null) { return; }
        if (mPairingSlot >= 0) { return; }
        var slot = mPendingPairSlot;
        var result = mPendingPairResult;
        var name = mPendingPairName;
        mPendingPairSlot = -1;
        mPendingPairResult = null;
        mPendingPairName = "";
        if (!mWant[slot] || !needsDevice(slot)) { return; }
        if (!slotConnected(slot)) { return; }
        if (mPhase != phaseForSlot(slot)) { return; }
        if (activeSlot() != slot) { return; }
        try {
            if (slot == DEV_HRM || slot == DEV_PM) {
                mDeviceName[slot] = name;
            }
            if (slot == DEV_DI2) {
                mCachedScanResult[slot] = result;
                mDi2ProbeScanResult = result;
                mDi2ProbeIdMatch = matchesScanIdentity(DEV_DI2, result);
                mDi2SerialReadAttempts = 0;
            }
            BluetoothLowEnergy.pairDevice(result);
            mPairingSlot = slot;
            mDevState[slot] = DS_PAIRING;
            mPairStartTick = mTickCount;
            mScanBackoff = SCAN_PAUSE;
            try { BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF); } catch (exOff) {}
            mMgrState = MGR_RUNNING;
            if (slot != DEV_DI2) {
                markIdentityTrusted(slot);
            }
        } catch (ex) {
            if (slot == DEV_DI2) {
                mCachedScanResult[slot] = null;
            }
            mErrorMsg = "pair:" + ex.getErrorMessage();
        }
    }

    private function needsDevice(slot as Number) as Boolean {
        var st = mDevState[slot];
        return st == DS_IDLE || st == DS_DISCONNECTED;
    }

    private function hasShimanoManuf(result as BluetoothLowEnergy.ScanResult) as Boolean {
        try {
            return result.getManufacturerSpecificData(1098) != null;
        } catch (ex) {}
        return false;
    }

    private function scanUuidFlags(result as BluetoothLowEnergy.ScanResult) as Array<Boolean> {
        var flags = [false, false, false] as Array<Boolean>;
        try {
            var uuids = result.getServiceUuids();
            var item = uuids.next();
            while (item != null) {
                var u = item as BluetoothLowEnergy.Uuid;
                if (mHrmSvcUuid != null && u.equals(mHrmSvcUuid)) { flags[DEV_HRM] = true; }
                if (mPmSvcUuid != null && u.equals(mPmSvcUuid)) { flags[DEV_PM] = true; }
                if (mShimanoBleUuid != null && u.equals(mShimanoBleUuid)) { flags[DEV_DI2] = true; }
                item = uuids.next();
            }
        } catch (ex) {}
        return flags;
    }

    private function scanHasShimanoAdvUuid(result as BluetoothLowEnergy.ScanResult) as Boolean {
        if (mShimanoAdvUuid == null) { return false; }
        try {
            var uuids = result.getServiceUuids();
            var item = uuids.next();
            while (item != null) {
                if ((item as BluetoothLowEnergy.Uuid).equals(mShimanoAdvUuid)) {
                    return true;
                }
                item = uuids.next();
            }
        } catch (ex) {}
        return false;
    }

    private function identifyDevice(result as BluetoothLowEnergy.ScanResult) as Number {
        if (slotWanted(DEV_DI2) && needsDevice(DEV_DI2) && isShimanoScanResult(result)) {
            return DEV_DI2;
        }
        var flags = scanUuidFlags(result);
        if (flags[DEV_HRM] && mWant[DEV_HRM] && needsDevice(DEV_HRM)) { return DEV_HRM; }
        if (flags[DEV_PM] && mWant[DEV_PM] && needsDevice(DEV_PM)) { return DEV_PM; }
        return -1;
    }

    function onScanChanged(scanState as BluetoothLowEnergy.ScanState, status as BluetoothLowEnergy.Status) as Void {
        if (scanState != BluetoothLowEnergy.SCAN_STATE_SCANNING && mMgrState == MGR_SCANNING) {
            mMgrState = MGR_RUNNING;
        }
        if (scanState == BluetoothLowEnergy.SCAN_STATE_SCANNING && mIdentityScanWindows == 0) {
            resetScanCandidate();
        }
        if (scanState == BluetoothLowEnergy.SCAN_STATE_SCANNING) {
            mLastScanHadRegisteredAntId[DEV_DI2] = false;
        }
        mDi2ProbeScanResult = null;
        mDi2ProbeIdMatch = false;
        mDi2SerialReadAttempts = 0;
        mDi2RejectedScans = [] as Array<BluetoothLowEnergy.ScanResult>;
    }

    private function isRejectedDevice(result as BluetoothLowEnergy.ScanResult) as Boolean {
        for (var j = 0; j < mDi2RejectedScans.size(); j++) {
            try {
                if (result.isSameDevice(mDi2RejectedScans[j])) {
                    return true;
                }
            } catch (exRej) {}
        }
        try {
            var name = result.getDeviceName();
            if (name != null && !name.equals("")) {
                for (var i = 0; i < mRejectedDeviceNames.size(); i++) {
                    if (mRejectedDeviceNames[i].equals(name)) {
                        return true;
                    }
                }
            }
        } catch (ex) {}
        return false;
    }

    private function hasAntIds(slot as Number) as Boolean {
        return mCandIdCount[slot] > 0;
    }

    private function charIsDigitStr(s as String) as Boolean {
        // Avoid String.compareTo (API 5.0+) — Edge 530 is minApiLevel 3.3.0
        if (s == null || s.length() != 1) { return false; }
        return "0123456789".find(s) != null;
    }

    function clearCandidates(slot as Number) as Void {
        if (slot < 0 || slot >= DEV_COUNT) { return; }
        mCandIdCount[slot] = 0;
        mGarminNameCount[slot] = 0;
        // Keep mMatchBleAddr — Di2 MAC from SensorInfo / storage must survive per-tick ID refresh
    }

    // Di2 BLE identity: ANT serial in ad name at scan, or Device Info 0x2a25 after connect.
    function addBleAddress(slot as Number, addr as ByteArray) as Void {
        // Legacy — Di2 no longer pairs on MAC (unreliable on Edge 530 scan)
    }

    function hasBleAddress(slot as Number) as Boolean {
        return false;
    }

    private function loadStoredDi2Serial() as Void {
        try {
            var v = Storage.getValue("bleDi2Serial");
            if (v instanceof Number && (v as Number) > 0) {
                addCandidateId(DEV_DI2, v as Number);
            }
        } catch (ex) {}
    }

    private function persistDi2Serial(serial as Number) as Void {
        if (serial <= 0) { return; }
        try {
            var prev = Storage.getValue("bleDi2Serial");
            if (prev instanceof Number && (prev as Number) == serial) {
                return;
            }
        } catch (ex0) {}
        try { Storage.setValue("bleDi2Serial", serial); } catch (ex) {}
    }

    private function addCandIdRaw(slot as Number, id as Number) as Void {
        if (id <= 0 || mCandIdCount[slot] >= MAX_CAND_IDS) { return; }
        var base = slot * MAX_CAND_IDS;
        for (var i = 0; i < mCandIdCount[slot]; i++) {
            if (mCandIds[base + i] == id) { return; }
        }
        mCandIds[base + mCandIdCount[slot]] = id;
        mCandIdCount[slot] = mCandIdCount[slot] + 1;
    }

    // Add ID plus 16-bit form BLE ads often embed (digit-run matcher covers truncated tails)
    function addCandidateId(slot as Number, id as Number) as Void {
        if (slot < 0 || slot >= DEV_COUNT || id <= 0) { return; }
        addCandIdRaw(slot, id);
        var id16 = id & 0xFFFF;
        if (id16 > 0 && id16 != id) { addCandIdRaw(slot, id16); }
    }

    // Garmin Sensors & Accessories entry — name for display only; id for match / name resolve
    function addGarminSensor(slot as Number, name as String, id as Number) as Void {
        if (slot < 0 || slot >= DEV_COUNT) { return; }
        if (name == null || name.equals("")) { return; }
        if (mGarminNameCount[slot] >= MAX_GARM_NAMES) { return; }
        var base = slot * MAX_GARM_NAMES;
        for (var i = 0; i < mGarminNameCount[slot]; i++) {
            if (mGarminNames[base + i].equals(name)) {
                if (id > 0 && mGarminIds[base + i] <= 0) {
                    mGarminIds[base + i] = id;
                }
                return;
            }
        }
        var idx = base + mGarminNameCount[slot];
        mGarminNames[idx] = name;
        mGarminIds[idx] = id > 0 ? id : 0;
        mGarminNameCount[slot] = mGarminNameCount[slot] + 1;
    }

    private function markIdentityTrusted(slot as Number) as Void {
        if (slot >= 0 && slot < DEV_COUNT) {
            mIdentityTrusted[slot] = true;
        }
    }

    private function pow10(n as Number) as Number {
        var v = 1;
        for (var i = 0; i < n; i++) {
            v = v * 10;
        }
        return v;
    }

    private function parseDigitRun(run as String) as Number {
        // Base 10 — avoid octal interpretation of leading zeros ("014117")
        var n = run.toNumberWithBase(10);
        if (n == null) { return -1; }
        return n as Number;
    }

    // True if BLE digit-run matches full/truncated ANT ID
    // e.g. name "HRM-Dual:014117" vs candidate 1014117
    private function digitRunMatchesId(run as String, id as Number) as Boolean {
        if (run.equals("") || id <= 0) { return false; }
        var idStr = id.toString();
        if (run.equals(idStr)) { return true; }

        var runLen = run.length();
        // Prefer whole digit-runs of at least 4 digits (avoids weak short matches)
        if (runLen < 4) { return false; }

        // Exact string suffix: "...1014117" ends with "014117"
        var idLen = idStr.length();
        if (idLen >= runLen) {
            var tail = idStr.substring(idLen - runLen, idLen);
            if (tail != null && tail.equals(run)) { return true; }
        }

        var runVal = parseDigitRun(run);
        if (runVal <= 0) { return false; }
        if (runVal == id) { return true; }

        // Numeric suffix with leading zeros: "014117" → 14117, 1014117 % 10^6 == 14117
        var mod = pow10(runLen);
        if (mod > 0 && (id % mod) == runVal) { return true; }

        // Significant digits only (strip leading zeros in the run)
        var sig = run;
        while (sig.length() > 1) {
            var first = sig.substring(0, 1);
            if (first == null || !first.equals("0")) { break; }
            var rest = sig.substring(1, sig.length());
            if (rest == null) { break; }
            sig = rest;
        }
        if (sig.length() >= 4 && !sig.equals(run)) {
            if (idStr.equals(sig)) { return true; }
            if (idLen >= sig.length()) {
                var tail2 = idStr.substring(idLen - sig.length(), idLen);
                if (tail2 != null && tail2.equals(sig)) { return true; }
            }
            var mod2 = pow10(sig.length());
            if (mod2 > 0 && (id % mod2) == runVal) { return true; }
        }
        return false;
    }

    // True if any digit-run in BLE name matches a candidate ANT ID (full or truncated)
    private function nameContainsAntId(name as String, id as Number) as Boolean {
        if (name.equals("") || id <= 0) { return false; }
        var nameLen = name.length();
        var i = 0;
        while (i < nameLen) {
            if (!charIsDigitStr(name.substring(i, i + 1))) {
                i++;
                continue;
            }
            var j = i + 1;
            while (j < nameLen && charIsDigitStr(name.substring(j, j + 1))) {
                j++;
            }
            var run = name.substring(i, j);
            if (run != null && digitRunMatchesId(run, id)) {
                return true;
            }
            i = j;
        }
        return false;
    }

    private function nameMatchesAnyAntId(slot as Number, name as String?) as Boolean {
        if (name == null || name.equals("")) { return false; }
        var base = slot * MAX_CAND_IDS;
        for (var i = 0; i < mCandIdCount[slot]; i++) {
            var id = mCandIds[base + i];
            if (id > 0 && nameContainsAntId(name, id)) {
                return true;
            }
        }
        return false;
    }

    // PM/HRM: ANT ID in BLE ad name. Di2: stored MAC via matchesScanIdentity only.
    private function matchesSlotIdentity(slot as Number, name as String?) as Boolean {
        if (slot == DEV_DI2) {
            return false;
        }
        if (hasAntIds(slot)) {
            return nameMatchesAnyAntId(slot, name);
        }
        if (slot == DEV_HRM || slot == DEV_PM) {
            return true;
        }
        var stored = mStoredName[slot];
        if (stored.equals("")) {
            return false;
        }
        return name != null && name.equals(stored);
    }

    // Garmin registered name or ANT id embedded in BLE ad name
    private function nameMatchesGarminEntry(slot as Number, name as String?) as Boolean {
        if (name == null || name.equals("") || mGarminNameCount[slot] <= 0) {
            return false;
        }
        var base = slot * MAX_GARM_NAMES;
        for (var i = 0; i < mGarminNameCount[slot]; i++) {
            var gName = mGarminNames[base + i];
            if (!gName.equals("") && name.equals(gName)) {
                return true;
            }
            var gid = mGarminIds[base + i];
            if (gid > 0 && nameContainsAntId(name, gid)) {
                return true;
            }
            var g16 = gid & 0xFFFF;
            if (g16 > 0 && g16 != gid && nameContainsAntId(name, g16)) {
                return true;
            }
        }
        return false;
    }

    private function matchesScanIdentity(slot as Number, result as BluetoothLowEnergy.ScanResult) as Boolean {
        var dn = scanBleNameFromResult(result);
        if (bleNameMatchesAnyGarminEntryStrict(slot, dn)) {
            return true;
        }
        if (bleNameMatchesAnyGarminEntryIdOnly(slot, dn)) {
            return true;
        }
        if (nameMatchesAnyAntId(slot, dn)) {
            return true;
        }
        return false;
    }

    function onScanResult(scanResults as BluetoothLowEnergy.Iterator) as Void {
        if (!mProfileRegistered) { return; }
        try {
            onScanResultInner(scanResults);
        } catch (ex) {
            mErrorMsg = "scanR:" + ex.getErrorMessage();
        }
    }

    private function onScanResultInner(scanResults as BluetoothLowEnergy.Iterator) as Void {
        var target = activeSlot();
        if (target == DEV_HRM || target == DEV_PM) {
            onHrmPmScanResults(target, scanResults);
            return;
        }
        var bestStrictResult = null;
        var bestStrictRssi = -999;
        var bestStrictEntry = -1;
        var bestIdResult = null;
        var bestIdRssi = -999;
        var bestIdEntry = -1;
        var bestSignalResult = null;
        var bestSignalRssi = -999;
        var batchHasRegAntId = false;

        var sr = scanResults.next();
        while (sr != null) {
            var result = sr as BluetoothLowEnergy.ScanResult;
            mScanDeviceCount++;

            if (mDebugVerbose) {
                var info = "#" + mScanDeviceCount;
                try {
                    var name = result.getDeviceName();
                    if (name != null && !name.equals("")) {
                        info = info + " " + name;
                    }
                } catch (ex) {}
                try {
                    var uuids = result.getServiceUuids();
                    var item = uuids.next();
                    while (item != null) {
                        var u = item as BluetoothLowEnergy.Uuid;
                        var s = u.toString();
                        info = info + " " + s.substring(4, 8);
                        item = uuids.next();
                    }
                } catch (ex2) {}
                mLastScanInfo = info;
            }

            var slot = identifyDevice(result);
            if (slot >= 0) {
                var dn = scanBleNameFromResult(result);
                try {
                    if (slot == DEV_DI2) {
                        mDi2ScanName = dn;
                    }
                    if (slot == DEV_DI2 && !dn.equals("") && mDeviceName[slot].equals("")) {
                        mDeviceName[slot] = dn;
                    }
                } catch (ex) {}
                if (slot == target && mPairingSlot < 0 && !isRejectedDevice(result)) {
                    if (bleNameContainsAnyRegisteredGarminAntId(slot, dn)) {
                        batchHasRegAntId = true;
                    }
                    var rssi = -999;
                    try { rssi = result.getRssi(); } catch (exRssi) {}
                    var matchInfo = bestEntryMatchForBleName(slot, dn);
                    var tier = matchInfo[0];
                    var entryIdx = matchInfo[1];
                    if (tier == MATCH_STRICT) {
                        if (isBetterScanMatch(slot, tier, rssi, entryIdx, MATCH_STRICT, bestStrictRssi, bestStrictEntry)) {
                            bestStrictRssi = rssi;
                            bestStrictEntry = entryIdx;
                            bestStrictResult = result;
                        }
                    } else if (tier == MATCH_ID) {
                        if (isBetterScanMatch(slot, tier, rssi, entryIdx, MATCH_ID, bestIdRssi, bestIdEntry)) {
                            bestIdRssi = rssi;
                            bestIdEntry = entryIdx;
                            bestIdResult = result;
                        }
                    } else if (isSignalTypeCandidate(slot, result)) {
                        if (rssi > bestSignalRssi) {
                            bestSignalRssi = rssi;
                            bestSignalResult = result;
                        }
                    }
                }
            }
            sr = scanResults.next();
        }

        if (target == DEV_DI2) {
            mLastScanHadRegisteredAntId[DEV_DI2] = batchHasRegAntId;
        }

        var bestResult = null;
        if (bestStrictResult != null) {
            bestResult = bestStrictResult;
        } else if (bestIdResult != null) {
            bestResult = bestIdResult;
        } else if (!batchHasRegAntId && allowSignalFallback(target)) {
            bestResult = bestSignalResult;
        }

        if (bestResult != null && mPairingSlot < 0 && mPendingPairSlot < 0) {
            mPendingPairSlot = target;
            mPendingPairResult = bestResult as BluetoothLowEnergy.ScanResult;
        }
    }

    private function onHrmPmScanResults(target as Number, scanResults as BluetoothLowEnergy.Iterator) as Void {
        var freshBest = null;
        var freshBestName = "";
        var freshBestRssi = -999;
        var sr = scanResults.next();
        while (sr != null) {
            var result = sr as BluetoothLowEnergy.ScanResult;
            mScanDeviceCount++;
            var bleName = scanBleNameFromResult(result);

            if (mDebugVerbose) {
                var info = "#" + mScanDeviceCount;
                if (!bleName.equals("")) { info = info + " " + bleName; }
                mLastScanInfo = info;
            }

            if (isSignalTypeCandidate(target, result) && !isRejectedDevice(result)) {
                if (mReacquireScanSlot == target) {
                    if (mReacquireScanName.equals("") || bleName.equals(mReacquireScanName)) {
                        var rssi = -999;
                        try { rssi = result.getRssi(); } catch (exRssi) {}
                        if (freshBest == null || rssi > freshBestRssi) {
                            freshBest = result;
                            freshBestName = bleName;
                            freshBestRssi = rssi;
                        }
                    }
                } else if (mReacquireScanSlot < 0) {
                    considerScanCandidate(target, result, bleName);
                }
            }
            sr = scanResults.next();
        }
        if (freshBest != null && mPairingSlot < 0 && mPendingPairSlot < 0) {
            mPendingPairSlot = target;
            mPendingPairResult = freshBest as BluetoothLowEnergy.ScanResult;
            mPendingPairName = freshBestName.equals("") ? mReacquireScanName : freshBestName;
            resetReacquireCandidate();
            resetScanCandidate();
        }
    }

    function onConnectionChanged(device as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            var slot = mPairingSlot;
            if (slot < 0) {
                try { BluetoothLowEnergy.unpairDevice(device); } catch (ex) {}
                return;
            }
            mPairingSlot = -1;
            mDevices[slot] = device;
            mDevState[slot] = DS_SUBSCRIBING;
            try {
                var devName = device.getName();
                if (devName != null && !devName.equals("") && mDeviceName[slot].equals("")) {
                    mDeviceName[slot] = devName;
                }
            } catch (ex) {}
            subscribeToServices(device, slot);
            return;
        }

        var slot = findDeviceSlot(device);
        if (slot < 0) {
            if (mPairingSlot >= 0) {
                slot = mPairingSlot;
                mPairingSlot = -1;
            } else {
                try { BluetoothLowEnergy.unpairDevice(device); } catch (ex) {}
                return;
            }
        }
        try { BluetoothLowEnergy.unpairDevice(device); } catch (ex) {}
        mDevices[slot] = null;
        mBatteryChars[slot] = null;
        mSerialChars[slot] = null;
        mDevState[slot] = DS_DISCONNECTED;
        mIdentityTrusted[slot] = false;
    }

    private function subscribeToServices(device as BluetoothLowEnergy.Device, slot as Number) as Void {
        mSubscribingSlot = slot;
        mBattSvcFound = false;
        mBattCharFound = false;
        if (mDebugVerbose) {
            mSubResult = "s" + slot;
            try {
                var svcIter = device.getServices();
                var svc = svcIter.next();
                var svcList = "";
                while (svc != null) {
                    var svcObj = svc as BluetoothLowEnergy.Service;
                    var uStr = svcObj.getUuid().toString();
                    svcList = svcList + " " + uStr.substring(4, 8);
                    svc = svcIter.next();
                }
                mServiceDiscoveryResult = "Svcs:" + (svcList.equals("") ? " none" : svcList);
            } catch (ex) {
                mServiceDiscoveryResult = "Svcs:err";
            }
        } else {
            mSubResult = "";
            mServiceDiscoveryResult = "";
        }

        if (slot == DEV_DI2) {
            mDi2SerialReadAttempts = 0;
            if (requestDi2SerialRead(device)) {
                return;
            }
            if (mDi2ProbeIdMatch || di2ScanNameMatchesAnt()) {
                markIdentityTrusted(DEV_DI2);
                continueDi2BatterySubscribe(device, DEV_DI2);
                return;
            }
            rejectDi2Probe();
            return;
        }

        try {
            var battSvc = device.getService(mBatterySvcUuid);
            if (battSvc != null) {
                mBattSvcFound = true;
                if (mDebugVerbose) { mSubResult = mSubResult + " bSvc"; }
                var battChar = battSvc.getCharacteristic(mBatteryCharUuid);
                if (battChar != null) {
                    mBattCharFound = true;
                    if (mDebugVerbose) { mSubResult = mSubResult + " bChr"; }
                    mBatteryChars[slot] = battChar;
                    try {
                        battChar.requestRead();
                    } catch (ex) {
                        if (mDebugVerbose) { mSubResult = mSubResult + " rdE"; }
                    }
                }
            } else if (mDebugVerbose) {
                mSubResult = mSubResult + " noBSvc";
            }
        } catch (ex) {
            if (mDebugVerbose) { mSubResult = mSubResult + " battE"; }
        }

        finishSubscribe();
    }

    private function continueDi2BatterySubscribe(device as BluetoothLowEnergy.Device, slot as Number) as Void {
        try {
            var battSvc = device.getService(mBatterySvcUuid);
            if (battSvc != null) {
                mBattSvcFound = true;
                if (mDebugVerbose) { mSubResult = mSubResult + " bSvc"; }
                var battChar = battSvc.getCharacteristic(mBatteryCharUuid);
                if (battChar != null) {
                    mBattCharFound = true;
                    if (mDebugVerbose) { mSubResult = mSubResult + " bChr"; }
                    mBatteryChars[slot] = battChar;
                    try {
                        battChar.requestRead();
                    } catch (ex) {
                        if (mDebugVerbose) { mSubResult = mSubResult + " rdE"; }
                    }
                }
            } else if (mDebugVerbose) {
                mSubResult = mSubResult + " noBSvc";
            }
        } catch (ex) {
            if (mDebugVerbose) { mSubResult = mSubResult + " battE"; }
        }
        finishSubscribe();
    }

    private function di2ScanNameMatchesAnt() as Boolean {
        if (mDi2ScanName.equals("")) { return false; }
        return nameMatchesAnyAntId(DEV_DI2, mDi2ScanName) || nameMatchesGarminEntry(DEV_DI2, mDi2ScanName);
    }

    private function serialStringFromValue(value as Lang.ByteArray) as String {
        var s = "";
        for (var i = 0; i < value.size(); i++) {
            var b = value[i] & 0xFF;
            if (b >= 0x20 && b < 0x7F) {
                s = s + b.toChar().toString();
            }
        }
        return s;
    }

    private function serialMatchesDi2Candidates(serialStr as String) as Boolean {
        if (serialStr.equals("")) { return false; }
        if (!hasAntIds(DEV_DI2)) { return true; }
        var base = DEV_DI2 * MAX_CAND_IDS;
        for (var i = 0; i < mCandIdCount[DEV_DI2]; i++) {
            var id = mCandIds[base + i];
            if (id > 0 && nameContainsAntId(serialStr, id)) {
                return true;
            }
        }
        return false;
    }

    private function persistSerialFromString(serialStr as String) as Void {
        mDevSerial[DEV_DI2] = serialStr;
        var base = DEV_DI2 * MAX_CAND_IDS;
        for (var i = 0; i < mCandIdCount[DEV_DI2]; i++) {
            var id = mCandIds[base + i];
            if (id > 0 && nameContainsAntId(serialStr, id)) {
                persistDi2Serial(id);
                return;
            }
        }
        var n = parseDigitsToNumber(serialStr);
        if (n > 0) {
            addCandidateId(DEV_DI2, n);
            persistDi2Serial(n);
        }
    }

    private function parseDigitsToNumber(s as String) as Number {
        var acc = 0;
        var found = false;
        var len = s.length();
        for (var i = 0; i < len; i++) {
            var ch = s.substring(i, i + 1);
            if (ch != null && charIsDigitStr(ch)) {
                found = true;
                acc = acc * 10 + ch.toNumber();
            }
        }
        return found ? acc : 0;
    }

    private function requestDi2SerialRead(device as BluetoothLowEnergy.Device) as Boolean {
        try {
            var devInfoSvc = device.getService(mDevInfoSvcUuid);
            if (devInfoSvc == null) { return false; }
            var serialChar = devInfoSvc.getCharacteristic(mSerialCharUuid);
            if (serialChar == null) { return false; }
            mSerialChars[DEV_DI2] = serialChar;
            serialChar.requestRead();
            mDi2SerialReadAttempts++;
            if (mDebugVerbose) { mSubResult = mSubResult + " ser"; }
            return true;
        } catch (ex) {}
        return false;
    }

    private function addDi2RejectedScan(result as BluetoothLowEnergy.ScanResult) as Void {
        if (mDi2RejectedScans.size() >= DI2_REJECTED_SCAN_MAX) {
            mDi2RejectedScans = mDi2RejectedScans.slice(1, DI2_REJECTED_SCAN_MAX) as Array<BluetoothLowEnergy.ScanResult>;
        }
        mDi2RejectedScans.add(result);
    }

    private function rejectDi2Probe() as Void {
        if (mDi2ProbeScanResult != null) {
            addDi2RejectedScan(mDi2ProbeScanResult);
        }
        mDi2ProbeScanResult = null;
        mDi2ProbeIdMatch = false;
        mDi2SerialReadAttempts = 0;
        mIdentityTrusted[DEV_DI2] = false;
        forceDisconnectSlot(DEV_DI2);
    }

    private function completeDi2SerialRead(serialStr as String) as Void {
        if (!serialMatchesDi2Candidates(serialStr)) {
            rejectDi2Probe();
            return;
        }
        persistSerialFromString(serialStr);
        mDi2ProbeScanResult = null;
        mDi2ProbeIdMatch = false;
        markIdentityTrusted(DEV_DI2);
        var device = mDevices[DEV_DI2];
        if (device != null) {
            continueDi2BatterySubscribe(device, DEV_DI2);
        }
    }

    private function processDi2SerialRead(status as BluetoothLowEnergy.Status, value as Lang.ByteArray) as Void {
        if (status == BluetoothLowEnergy.STATUS_SUCCESS && value != null && value.size() > 0) {
            completeDi2SerialRead(serialStringFromValue(value));
            return;
        }
        var device = mDevices[DEV_DI2];
        if (device != null && mDi2SerialReadAttempts < DI2_SERIAL_READ_MAX && requestDi2SerialRead(device)) {
            return;
        }
        if (mDi2ProbeIdMatch || di2ScanNameMatchesAnt()) {
            markIdentityTrusted(DEV_DI2);
            if (device != null) {
                continueDi2BatterySubscribe(device, DEV_DI2);
            }
            return;
        }
        rejectDi2Probe();
    }

    private function finishSubscribe() as Void {
        if (mSubscribingSlot >= 0) {
            mDevState[mSubscribingSlot] = DS_ACTIVE;
        }
        mMgrState = MGR_RUNNING;
        mSubscribingSlot = -1;
    }

    function onCharRead(char as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status, value as Lang.ByteArray) as Void {
        try {
            if (mSerialCharUuid != null && char.getUuid().equals(mSerialCharUuid)) {
                processDi2SerialRead(status, value);
                return;
            }
        } catch (exSer) {}
        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            processValue(char, value);
        }
    }

    function onCharChanged(char as BluetoothLowEnergy.Characteristic, value as Lang.ByteArray) as Void {
        processValue(char, value);
    }

    private function findCharSlot(chars as Array<BluetoothLowEnergy.Characteristic?>, char as BluetoothLowEnergy.Characteristic) as Number {
        for (var i = 0; i < DEV_COUNT; i++) {
            if (chars[i] != null && chars[i] == char) {
                return i;
            }
        }
        return -1;
    }

    private function processValue(char as BluetoothLowEnergy.Characteristic, value as Lang.ByteArray) as Void {
        var serialSlot = findCharSlot(mSerialChars, char);
        if (serialSlot >= 0) {
            var s = "";
            for (var i = 0; i < value.size(); i++) {
                var b = value[i] & 0xFF;
                if (b >= 0x20 && b < 0x7F) {
                    s = s + b.toChar().toString();
                }
            }
            mDevSerial[serialSlot] = s;
            return;
        }

        var battSlot = findCharSlot(mBatteryChars, char);
        if (battSlot >= 0) {
            processBatteryValue(battSlot, value);
        }
    }

    private function processBatteryValue(slot as Number, value as Lang.ByteArray) as Void {
        if (!isNameMatch(slot)) { return; }
        if (value.size() < 1) { return; }
        var pct = value[0] & 0xFF;
        if (pct > 100) { return; }
        mDevBatteryPct[slot] = pct;
        mBatteryRead[slot] = true;
        if (slot == DEV_HRM || slot == DEV_PM) {
            mBatterySourceName[slot] = mDeviceName[slot];
            mFallbackBattery[slot] = mLiveAntTarget[slot] > 0
                ? !nameMatchesLiveAntTarget(slot, mDeviceName[slot])
                : bestEntryMatchForBleName(slot, mDeviceName[slot])[0] < MATCH_ID;
        }
        if (slot != DEV_HRM) {
            mRetryCount[slot] = 0;
            mNeedsRefresh[slot] = false;
            // Drop session ScanResult once battery is known (not in refresh/pairing window)
            if (mDevState[slot] != DS_PAIRING && mDevState[slot] != DS_SUBSCRIBING) {
                clearCachedScanResult(slot);
            }
        }
        if (slot == DEV_DI2 && !mSensorsScanned && mStoredName[slot].equals("") && !mDeviceName[slot].equals("")) {
            storeDeviceName(slot, mDeviceName[slot]);
        }
    }

    private function storeDeviceName(slot as Number, name as String) as Void {
        if (slot != DEV_DI2) { return; }
        mStoredName[slot] = name;
        try { Storage.setValue("bleDi2Name", name); } catch (ex) {}
        checkAllNamesStored();
    }

    private function checkAllNamesStored() as Void {
        // PM/HRM identity comes from ANT IDs; only Di2 still needs a stored BLE name
        if (mWant[DEV_DI2] && mStoredName[DEV_DI2].equals("")) {
            return;
        }
        mSensorsScanned = true;
        try { Storage.setValue("bleSensorsScanned", true); } catch (ex) {}
    }

    private function isNameMatch(slot as Number) as Boolean {
        // Pairing already validated by ID / MAC / service UUID — getName() often null or renamed
        if (mIdentityTrusted[slot]) {
            return true;
        }
        var current = mDeviceName[slot];
        if (slot == DEV_HRM || slot == DEV_PM) {
            if (mDevState[slot] == DS_ACTIVE || mDevState[slot] == DS_SUBSCRIBING) {
                markIdentityTrusted(slot);
                return true;
            }
            if (!hasAntIds(slot)) {
                markIdentityTrusted(slot);
                return true;
            }
            if (nameMatchesAnyAntId(slot, current)) {
                markIdentityTrusted(slot);
                return true;
            }
            // Connected via UUID fallback — name may not include ANT id suffix
            markIdentityTrusted(slot);
            return true;
        }
        // Di2: verified via ANT serial (Device Info 0x2a25 or scan name id match)
        if (mIdentityTrusted[slot] || !mDevSerial[slot].equals("")) {
            markIdentityTrusted(slot);
            return true;
        }
        mErrorMsg = "nm" + slot + ":noSer";
        return false;
    }

    private function findDeviceSlot(device as BluetoothLowEnergy.Device) as Number {
        for (var i = 0; i < DEV_COUNT; i++) {
            if (mDevices[i] != null && mDevices[i] == device) {
                return i;
            }
        }
        return -1;
    }

    private function clearCachedScanResult(slot as Number) as Void {
        if (slot == DEV_DI2) {
            mCachedScanResult[slot] = null;
        }
    }

    function getDi2BatteryPercent() as Number { return mDevBatteryPct[DEV_DI2]; }
    function getDi2ScanName() as String { return mDi2ScanName; }
    function getHrmBatteryPercent() as Number { return mDevBatteryPct[DEV_HRM]; }
    function getPmBatteryPercent() as Number { return mDevBatteryPct[DEV_PM]; }
    function isPmBleExhausted() as Boolean { return mRetryCount[DEV_PM] >= MAX_RETRIES; }
    function getScanDeviceCount() as Number { return mScanDeviceCount; }
    function getErrorMsg() as String { return mErrorMsg; }
    function getHrmDeviceName() as String { return mDeviceName[DEV_HRM]; }
    function getDi2DeviceName() as String { return mDeviceName[DEV_DI2]; }
    function getPmDeviceName() as String { return mDeviceName[DEV_PM]; }
    function getStoredDi2Name() as String { return mStoredName[DEV_DI2]; }
    function getDeviceSerial(slot as Number) as String {
        if (slot < 0 || slot >= DEV_COUNT) { return ""; }
        return mDevSerial[slot];
    }

    // Di2 ads often have no name — prefer BLE Device Info SN, else first candidate ANT id
    function getDi2PairDebugLabel() as String {
        if (!mDevSerial[DEV_DI2].equals("")) { return "SN" + mDevSerial[DEV_DI2]; }
        var n = mDeviceName[DEV_DI2];
        if (!n.equals("") && !n.equals("(null)")) { return n; }
        if (!mDi2ScanName.equals("") && !mDi2ScanName.equals("(null)")) { return mDi2ScanName; }
        if (mCandIdCount[DEV_DI2] > 0) {
            return "SN" + mCandIds[DEV_DI2 * MAX_CAND_IDS].toString();
        }
        return "";
    }

    function getAntMatchDebug(slot as Number) as String {
        if (slot < 0 || slot >= DEV_COUNT) { return ""; }
        var s = "";
        var base = slot * MAX_CAND_IDS;
        for (var i = 0; i < mCandIdCount[slot]; i++) {
            if (i > 0) { s = s + ","; }
            s = s + mCandIds[base + i].toString();
        }
        return s;
    }

    // Garmin names only (no id suffix — id formatting was crashing on device)
    function getGarminNamesDebug(slot as Number) as String {
        if (slot < 0 || slot >= DEV_COUNT) { return ""; }
        var s = "";
        var base = slot * MAX_GARM_NAMES;
        for (var i = 0; i < mGarminNameCount[slot]; i++) {
            if (i > 0) { s = s + "|"; }
            s = s + mGarminNames[base + i];
        }
        return s;
    }

    // HRM/PM names belong to the battery that was actually accepted. Di2 keeps
    // its legacy paired-name behavior.
    function getPreferredDisplayName(slot as Number) as String {
        if (slot < 0 || slot >= DEV_COUNT) { return ""; }
        if (slot == DEV_HRM || slot == DEV_PM) {
            var sourceName = mBatterySourceName[slot];
            if (sourceName.equals("")) { return ""; }
            if (mFallbackBattery[slot]) { return sourceName; }
            var sourceBase = slot * MAX_GARM_NAMES;
            for (var j = 0; j < mGarminNameCount[slot]; j++) {
                var sourceId = mGarminIds[sourceBase + j];
                if (sourceId <= 0) { continue; }
                if (nameContainsAntId(sourceName, sourceId)) {
                    return mGarminNames[sourceBase + j];
                }
                var source16 = sourceId & 0xFFFF;
                if (source16 > 0 && source16 != sourceId && nameContainsAntId(sourceName, source16)) {
                    return mGarminNames[sourceBase + j];
                }
            }
            return sourceName;
        }
        var bleName = mDeviceName[slot];
        if (!bleName.equals("") && mGarminNameCount[slot] > 0) {
            var base = slot * MAX_GARM_NAMES;
            for (var i = 0; i < mGarminNameCount[slot]; i++) {
                var gid = mGarminIds[base + i];
                if (gid <= 0) { continue; }
                if (nameContainsAntId(bleName, gid)) {
                    return mGarminNames[base + i];
                }
                var g16 = gid & 0xFFFF;
                if (g16 > 0 && g16 != gid && nameContainsAntId(bleName, g16)) {
                    return mGarminNames[base + i];
                }
            }
        }
        if (mGarminNameCount[slot] > 0) {
            return mGarminNames[slot * MAX_GARM_NAMES];
        }
        return bleName;
    }

    function getDi2AntMatchDebug() as String { return getAntMatchDebug(DEV_DI2); }
    function getHrmAntMatchDebug() as String { return getAntMatchDebug(DEV_HRM); }
    function getPmAntMatchDebug() as String { return getAntMatchDebug(DEV_PM); }

    function clearStoredNames() as Void {
        mSensorsScanned = false;
        mRejectedDeviceNames = [] as Array<String>;
        mDi2RejectedScans = [] as Array<BluetoothLowEnergy.ScanResult>;
        for (var i = 0; i < DEV_COUNT; i++) {
            mStoredName[i] = "";
            mDeviceName[i] = "";
            clearCachedScanResult(i);
            mDevSerial[i] = "";
            clearCandidates(i);
            mIdentityTrusted[i] = false;
            mRetryCount[i] = 0;
            mNeedsRefresh[i] = true;
            mDevBatteryPct[i] = -1;
            mBatterySourceName[i] = "";
            mBatteryRead[i] = false;
            mLastRefreshTick[i] = 0;
            mFailedRetryTick[i] = 0;
            mFallbackBattery[i] = false;
            mSampleConnection[i] = false;
            mLastScanHadRegisteredAntId[i] = false;
            mLiveAntTarget[i] = 0;
        }
        mHrLastDataTick = -100;
        mPmAntConnected = false;
        mIdentityScanWindows = 0;
        mPendingPairName = "";
        resetScanCandidate();
        resetReacquireCandidate();
        // Di2 name + MAC; purge any legacy PM/HRM name keys from older builds
        try { Storage.deleteValue("bleDi2Name"); } catch (ex) {}
        try { Storage.deleteValue("bleDi2Addr"); } catch (ex) {}
        try { Storage.deleteValue("bleDi2Serial"); } catch (exSer) {}
        try { Storage.deleteValue("bleHrmName"); } catch (ex) {}
        try { Storage.deleteValue("blePmName"); } catch (ex) {}
        mMatchBleAddr[DEV_DI2] = null;
        mPhase = bootPhase();
        stop();
        start();
    }

    function getDevStateString(slot as Number) as String {
        var st = mDevState[slot];
        switch (st) {
            case DS_IDLE:          return "IDLE";
            case DS_PAIRING:       return "PAIR";
            case DS_SUBSCRIBING:   return "SUB";
            case DS_ACTIVE:        return "ACT";
            case DS_DISCONNECTED:  return "DISC";
        }
        return "?";
    }

    function getHrmStateString() as String {
        return getDevStateString(DEV_HRM);
    }

    function getPhaseString() as String {
        switch (mPhase) {
            case PHASE_HRM:      return "HRM";
            case PHASE_HRM_WAIT: return "H>P";
            case PHASE_PM:       return "PM";
            case PHASE_PM_WAIT:  return "P>D";
            case PHASE_DI2:      return "DI2";
            case PHASE_DI2_WAIT: return "D>H";
            case PHASE_IDLE:     return "IDLE";
        }
        return "?";
    }

    function getMgrStateString() as String {
        switch (mMgrState) {
            case MGR_OFF:       return "OFF";
            case MGR_SCANNING:  return "SCAN";
            case MGR_RUNNING:   return "RUN";
            case MGR_ERROR:     return "ERR";
            case MGR_IDLE:      return "IDLE";
        }
        return "?";
    }

    function getHrmDebugString() as String {
        var s = getMgrStateString() + " " + getPhaseString();
        s = s + " d" + mScanDeviceCount;
        if (!mErrorMsg.equals("")) {
            s = s + " E:" + mErrorMsg;
        }
        s = s + " " + mServiceDiscoveryResult;
        s = s + " bat:" + (mBattSvcFound ? "Y" : "N");
        s = s + " chr:" + (mBattCharFound ? "Y" : "N");
        if (!mLastScanInfo.equals("")) {
            s = s + " " + mLastScanInfo;
        }
        return s;
    }

    function setAntDeviceId(slot as Number, id as Number) as Void {
        addCandidateId(slot, id);
    }

    function setAntSerialId(slot as Number, serial as Number) as Void {
        addCandidateId(slot, serial);
    }

    // Legacy Di2 helpers
    function setAntSerial(serial as Number) as Void {
        addCandidateId(DEV_DI2, serial);
    }

    function setAntDeviceNumber(devNum as Number) as Void {
        addCandidateId(DEV_DI2, devNum);
    }

    // Disabled: Garmin :bleScanResult often stale — pairDevice can hard-crash the VM.
    function tryPairRegisteredScan(slot as Number, result as BluetoothLowEnergy.ScanResult) as Boolean {
        return false;
    }
}
