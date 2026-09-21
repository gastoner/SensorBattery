import Toybox.Activity;
import Toybox.Ant;
import Toybox.AntPlus;
import Toybox.Application.Properties;
import Toybox.Application.Storage;
import Toybox.BluetoothLowEnergy;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

class SensorBatteryView extends WatchUi.DataField {

    hidden var mShiftingListener as MyShiftingListener?;
    hidden var mShifting as AntPlus.Shifting?;

    hidden var mLightNetworkListener as MyLightNetworkListener?;
    hidden var mLightNetwork as AntPlus.LightNetwork?;

    hidden var mBikeRadarListener as MyBikeRadarListener?;
    hidden var mBikeRadar as AntPlus.BikeRadar?;

    hidden var mBikePowerListener as MyBikePowerListener?;
    hidden var mBikePower as AntPlus.BikePower?;

    hidden var mBikeCadenceListener as MyBikeCadenceListener?;
    hidden var mBikeCadence as AntPlus.BikeCadence?;

    hidden var mBikeSpeedListener as MyBikeSpeedListener?;
    hidden var mBikeSpeed as AntPlus.BikeSpeed?;

    hidden var mBleMgr as BleBatteryManager?;

    // PM left/right batteries (from AntPlus.BikePower)
    private var mPmLeftBatteryStatus as AntPlus.BatteryStatusValue;
    private var mPmLeftVoltage as Float or Null;
    private var mPmRightBatteryStatus as AntPlus.BatteryStatusValue;
    private var mPmRightVoltage as Float or Null;

    // Shifting component batteries (pre-formatted per component; reused buffer)
    private var mShiftDisplayParts as Array<String>;
    private var mShiftPartsCount as Number;
    private var mShiftWorstStatus as AntPlus.BatteryStatusValue;
    private var mShiftPartsFromAnt as Boolean;

    // Reused onUpdate row buffers (avoid [] each paint)
    private var mRowSortKeys as Array<Number>;
    private var mRowTexts as Array<String>;
    private var mRowColors as Array<Graphics.ColorValue>;
    private var mRowCount as Number;
    private var mFontLadder as Array<Graphics.FontType>;
    private var mFontXL as WatchUi.FontResource?;

    // Identity feed throttle / live-ID tracking
    private const FEED_IDENTITY_INTERVAL = 15;
    private var mNeedFullIdentityFeed as Boolean;
    private var mFeedIdentityTick as Number;
    private var mLastDi2AntConn as Boolean;
    private var mLastPmAntConn as Boolean;
    private var mLastFedDi2Num as Number;
    private var mLastFedDi2Serial as Number;
    private var mLastFedPmNum as Number;
    private var mLastFedPmSerial as Number;
    private var mLastFedHrmAntId as Number;
    private var mDi2RegCacheValid as Boolean;
    private var mCachedDi2RegIds as Array<Number>;
    private var mCachedDi2RegNames as Array<String>;
    private var mCachedDi2RegCount as Number;

    // Rear light battery (polled from radar Device, same device as light)
    private var mVariaBatteryStatus as AntPlus.BatteryStatusValue;
    private var mVariaVoltage as Float or Null;

    // Front light battery (from light network listener)
    private var mFrontLightBatteryStatus as AntPlus.BatteryStatusValue;
    private var mFrontLightVoltage as Float or Null;

    // Cadence sensor battery
    private var mCadenceBatteryStatus as AntPlus.BatteryStatusValue;
    private var mCadenceVoltage as Float or Null;

    // Speed sensor battery
    private var mSpeedBatteryStatus as AntPlus.BatteryStatusValue;
    private var mSpeedVoltage as Float or Null;

    // HR battery (from BLE)
    private var mHrBatteryPercent as Number;

    // PM battery (from BLE)
    private var mPmBleBatteryPercent as Number;

    // Head unit battery
    private var mDeviceBattery as Float;
    private var mDeviceCharging as Boolean;


    // Estimation tracking indices
    // User settings
    private var titleText as String = "Battery";
    private var showPmBattery as Boolean = true;
    private var showShiftingBattery as Boolean = true;
    private var showVaria as Boolean = true;
    private var showVariaMode as Boolean = true;
    private var showFrontLight as Boolean = true;
    private var showFrontLightMode as Boolean = true;
    private var showHrm as Boolean = true;
    private var showCadence as Boolean = true;
    private var showSpeed as Boolean = true;
    private var showDeviceBattery as Boolean = true;
    private var debugMode as Boolean = true;
    private var textZoom as Number = 0;

    // Sort positions (1-8)
    private var pmPosition as Number = 1;
    private var shifterPosition as Number = 2;
    private var rearPosition as Number = 3;
    private var frontPosition as Number = 4;
    private var hrmPosition as Number = 5;
    private var cadencePosition as Number = 6;
    private var speedPosition as Number = 7;
    private var devicePosition as Number = 8;

    function initialize() {
        DataField.initialize();

        mPmLeftBatteryStatus = AntPlus.BATT_STATUS_INVALID;
        mPmLeftVoltage = null;
        mPmRightBatteryStatus = AntPlus.BATT_STATUS_INVALID;
        mPmRightVoltage = null;
        mShiftDisplayParts = [] as Array<String>;
        mShiftPartsCount = 0;
        mShiftWorstStatus = AntPlus.BATT_STATUS_INVALID;
        mShiftPartsFromAnt = false;
        mRowSortKeys = [] as Array<Number>;
        mRowTexts = [] as Array<String>;
        mRowColors = [] as Array<Graphics.ColorValue>;
        mRowCount = 0;
        mFontXL = null;
        mFontLadder = [
            Graphics.FONT_XTINY,
            Graphics.FONT_TINY,
            Graphics.FONT_SMALL,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_LARGE
        ] as Array<Graphics.FontType>;
        mNeedFullIdentityFeed = true;
        mFeedIdentityTick = 0;
        mLastDi2AntConn = false;
        mLastPmAntConn = false;
        mLastFedDi2Num = 0;
        mLastFedDi2Serial = 0;
        mLastFedPmNum = 0;
        mLastFedPmSerial = 0;
        mLastFedHrmAntId = 0;
        mDi2RegCacheValid = false;
        mCachedDi2RegIds = [0, 0, 0] as Array<Number>;
        mCachedDi2RegNames = ["", "", ""] as Array<String>;
        mCachedDi2RegCount = 0;
        mVariaBatteryStatus = AntPlus.BATT_STATUS_INVALID;
        mVariaVoltage = null;
        mFrontLightBatteryStatus = AntPlus.BATT_STATUS_INVALID;
        mFrontLightVoltage = null;
        mCadenceBatteryStatus = AntPlus.BATT_STATUS_INVALID;
        mCadenceVoltage = null;
        mSpeedBatteryStatus = AntPlus.BATT_STATUS_INVALID;
        mSpeedVoltage = null;
        mHrBatteryPercent = -1;
        mPmBleBatteryPercent = -1;
        mDeviceBattery = 0.0;
        mDeviceCharging = false;

        try {
            mShiftingListener = new MyShiftingListener();
            mLightNetworkListener = new MyLightNetworkListener();
            mBikeRadarListener = new MyBikeRadarListener();
            mBikePowerListener = new MyBikePowerListener();
            mBikeCadenceListener = new MyBikeCadenceListener();
            mBikeSpeedListener = new MyBikeSpeedListener();
            loadSettings();
        } catch (ex) {
            // Survive initialization failures on devices with limited API support
        }
    }

    public function loadSettings() as Void {
        titleText = getStringProp("titleText", "Battery");
        showPmBattery = getBoolProp("showPmBattery", false);
        showShiftingBattery = getBoolProp("showShiftingBattery", true);
        showVaria = getBoolProp("showVaria", true);
        showVariaMode = getBoolProp("showVariaMode", true);
        showFrontLight = getBoolProp("showFrontLight", true);
        showFrontLightMode = getBoolProp("showFrontLightMode", true);
        showHrm = getBoolProp("showHrm", true);
        showCadence = getBoolProp("showCadence", true);
        showSpeed = getBoolProp("showSpeed", true);
        showDeviceBattery = getBoolProp("showDeviceBattery", true);
        debugMode = getBoolProp("debugMode", false);
        textZoom = getNumberProp("textZoom", 0);
        if (textZoom < -2) { textZoom = -2; }
        if (textZoom > 2) { textZoom = 2; }
        pmPosition = getNumberProp("pmPosition", 1);
        shifterPosition = getNumberProp("shifterPosition", 2);
        rearPosition = getNumberProp("rearPosition", 3);
        frontPosition = getNumberProp("frontPosition", 4);
        hrmPosition = getNumberProp("hrmPosition", 5);
        cadencePosition = getNumberProp("cadencePosition", 6);
        speedPosition = getNumberProp("speedPosition", 7);
        devicePosition = getNumberProp("devicePosition", 8);

        var rescan = getBoolProp("rescanSensors", false);
        if (rescan) {
            try { Storage.deleteValue("bleDi2Name"); } catch (ex) {}
            try { Storage.deleteValue("bleDi2Addr"); } catch (ex) {}
            try { Storage.deleteValue("bleDi2Serial"); } catch (exSer) {}
            try { Storage.deleteValue("bleHrmName"); } catch (ex) {}
            try { Storage.deleteValue("blePmName"); } catch (ex) {}
            try { Storage.deleteValue("bleSensorsScanned"); } catch (ex) {}
            try { Properties.setValue("rescanSensors", false); } catch (ex) {}
            mDi2RegCacheValid = false;
            mNeedFullIdentityFeed = true;
            if (mBleMgr != null) {
                mBleMgr.clearStoredNames();
            }
        }

        syncSensorLifecycle();
        if (mBleMgr != null) {
            mBleMgr.setDebugVerbose(debugMode);
            mNeedFullIdentityFeed = true;
        }
    }

    private function getBoolProp(key as String, fallback as Boolean) as Boolean {
        var val = Properties.getValue(key);
        if (val instanceof Boolean) { return val as Boolean; }
        return fallback;
    }

    private function getStringProp(key as String, fallback as String) as String {
        var val = Properties.getValue(key);
        if (val instanceof String) { return val as String; }
        return fallback;
    }

    private function getNumberProp(key as String, fallback as Number) as Number {
        var val = Properties.getValue(key);
        if (val instanceof Number) { return val as Number; }
        return fallback;
    }

    private function syncSensorLifecycle() as Void {
        if (Toybox.AntPlus has :BikePower) {
            if (showPmBattery && mBikePower == null && mBikePowerListener != null) {
                try {
                    mBikePower = new AntPlus.BikePower(mBikePowerListener);
                } catch (ex) {
                    mBikePower = null;
                }
            } else if (!showPmBattery) {
                mBikePower = null;
            }
        }

        if (Toybox.AntPlus has :Shifting) {
            if (showShiftingBattery && mShifting == null && mShiftingListener != null) {
                try {
                    mShifting = new AntPlus.Shifting(mShiftingListener);
                } catch (ex) {
                    mShifting = null;
                }
            } else if (!showShiftingBattery) {
                mShifting = null;
            }
        }

        var needBle = showShiftingBattery || showHrm || showPmBattery;
        if (needBle && mBleMgr == null) {
            try {
                mBleMgr = new BleBatteryManager(showShiftingBattery, showHrm, showPmBattery);
                mBleMgr.setDebugVerbose(debugMode);
                mBleMgr.start();
            } catch (ex) {
                mBleMgr = null;
            }
            mNeedFullIdentityFeed = true;
            mDi2RegCacheValid = false;
        } else if (!needBle && mBleMgr != null) {
            mBleMgr.stop();
            mBleMgr = null;
        } else if (mBleMgr != null) {
            mBleMgr.setDebugVerbose(debugMode);
        }

        if (showVaria || showFrontLight) {
            if (Toybox.AntPlus has :LightNetwork) {
                if (mLightNetwork == null && mLightNetworkListener != null) {
                    try {
                        mLightNetwork = new AntPlus.LightNetwork(mLightNetworkListener);
                    } catch (ex) {
                        mLightNetwork = null;
                    }
                }
            }
            if (Toybox.AntPlus has :BikeRadar) {
                if (mBikeRadar == null && mBikeRadarListener != null) {
                    try {
                        mBikeRadar = new AntPlus.BikeRadar(mBikeRadarListener);
                    } catch (ex) {
                        mBikeRadar = null;
                    }
                }
            }
        } else {
            mLightNetwork = null;
            mBikeRadar = null;
        }

        if (Toybox.AntPlus has :BikeCadence) {
            if (showCadence && mBikeCadence == null && mBikeCadenceListener != null) {
                try {
                    mBikeCadence = new AntPlus.BikeCadence(mBikeCadenceListener);
                } catch (ex) {
                    mBikeCadence = null;
                }
            } else if (!showCadence) {
                mBikeCadence = null;
            }
        }

        if (Toybox.AntPlus has :BikeSpeed) {
            if (showSpeed && mBikeSpeed == null && mBikeSpeedListener != null) {
                try {
                    mBikeSpeed = new AntPlus.BikeSpeed(mBikeSpeedListener);
                } catch (ex) {
                    mBikeSpeed = null;
                }
            } else if (!showSpeed) {
                mBikeSpeed = null;
            }
        }
    }

    function onLayout(dc as Dc) as Void {
        View.setLayout(Rez.Layouts.MainLayout(dc));
        if (dc.getWidth() < 400) {
            return;
        }
        if (mFontXL == null) {
            mFontXL = WatchUi.loadResource(Rez.Fonts.customFontXL) as WatchUi.FontResource;
        }
        mFontLadder = [
            Graphics.FONT_XTINY,
            Graphics.FONT_TINY,
            Graphics.FONT_SMALL,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_LARGE,
            mFontXL as WatchUi.FontResource
        ] as Array<Graphics.FontType>;
    }

    function compute(info as Activity.Info) as Void {
        try {
            computeInner(info);
        } catch (ex) {
        }
    }

    private function computeInner(info as Activity.Info) as Void {
        if (mBikePower != null) {
            try {
                var bp = mBikePower as AntPlus.BikePower;
                var ids = bp.getComponentIdentifiers();
                if (ids != null && ids.size() > 0) {
                    var batt = bp.getBatteryStatus(ids[0]);
                    if (batt != null && batt.batteryStatus != null) {
                        mPmLeftBatteryStatus = batt.batteryStatus;
                        if (batt.batteryVoltage != null) { mPmLeftVoltage = batt.batteryVoltage as Float; }
                    }
                    if (ids.size() > 1) {
                        var batt2 = bp.getBatteryStatus(ids[1]);
                        if (batt2 != null && batt2.batteryStatus != null) {
                            mPmRightBatteryStatus = batt2.batteryStatus;
                            if (batt2.batteryVoltage != null) { mPmRightVoltage = batt2.batteryVoltage as Float; }
                        }
                    }
                }
                if (mPmRightBatteryStatus == AntPlus.BATT_STATUS_INVALID) {
                    for (var probe = 0; probe < 8 && mPmRightBatteryStatus == AntPlus.BATT_STATUS_INVALID; probe++) {
                        var alreadyUsed = false;
                        if (ids != null) {
                            for (var j = 0; j < ids.size(); j++) {
                                if (ids[j] == probe) { alreadyUsed = true; break; }
                            }
                        }
                        if (alreadyUsed) { continue; }
                        var pb = bp.getBatteryStatus(probe);
                        if (pb != null && pb.batteryStatus != null && pb.batteryStatus != AntPlus.BATT_STATUS_INVALID) {
                            mPmRightBatteryStatus = pb.batteryStatus;
                            if (pb.batteryVoltage != null) { mPmRightVoltage = pb.batteryVoltage as Float; }
                        }
                    }
                }
            } catch (ex) {}
        }

        if (mBikeCadence != null && mBikeCadenceListener != null && mBikeCadenceListener.isConnected()) {
            try {
                var cad = mBikeCadence as AntPlus.BikeCadence;
                var cadIds = cad.getComponentIdentifiers();
                if (cadIds != null && cadIds.size() > 0) {
                    var cadBatt = cad.getBatteryStatus(cadIds[0]);
                    if (cadBatt != null && cadBatt.batteryStatus != null) {
                        mCadenceBatteryStatus = cadBatt.batteryStatus;
                        if (cadBatt.batteryVoltage != null) { mCadenceVoltage = cadBatt.batteryVoltage as Float; }
                    }
                }
            } catch (ex) {}
        }

        if (mBikeSpeed != null && mBikeSpeedListener != null && mBikeSpeedListener.isConnected()) {
            try {
                var spd = mBikeSpeed as AntPlus.BikeSpeed;
                var spdIds = spd.getComponentIdentifiers();
                if (spdIds != null && spdIds.size() > 0) {
                    var spdBatt = spd.getBatteryStatus(spdIds[0]);
                    if (spdBatt != null && spdBatt.batteryStatus != null) {
                        mSpeedBatteryStatus = spdBatt.batteryStatus;
                        if (spdBatt.batteryVoltage != null) { mSpeedVoltage = spdBatt.batteryVoltage as Float; }
                    }
                }
            } catch (ex) {}
        }
        if (mShifting != null && mShiftingListener != null && mShiftingListener.isConnected()) {
            try {
                var shift = mShifting as AntPlus.Shifting;
                var sIds = shift.getComponentIdentifiers();
                var partsCount = 0;
                var worst = AntPlus.BATT_STATUS_INVALID;
                if (sIds != null) {
                    for (var i = 0; i < sIds.size() && i < 6; i++) {
                        var batt = shift.getBatteryStatus(sIds[i]);
                        if (batt != null && batt.batteryStatus != null && batt.batteryStatus != AntPlus.BATT_STATUS_INVALID) {
                            var pct = batteryStatusToString(batt.batteryStatus);
                            var label = shiftComponentLabel(sIds[i]);
                            setShiftPart(partsCount, label + pct);
                            partsCount++;
                            worst = worstBatteryStatus(worst, batt.batteryStatus);
                        }
                    }
                }
                if (partsCount == 0) {
                    for (var i = 0; i < 8; i++) {
                        var batt = shift.getBatteryStatus(i);
                        if (batt != null && batt.batteryStatus != null && batt.batteryStatus != AntPlus.BATT_STATUS_INVALID) {
                            var pct = batteryStatusToString(batt.batteryStatus);
                            var label = shiftComponentLabel(i);
                            setShiftPart(partsCount, label + pct);
                            partsCount++;
                            worst = worstBatteryStatus(worst, batt.batteryStatus);
                        }
                    }
                }
                if (partsCount > 0) {
                    mShiftPartsCount = partsCount;
                    mShiftWorstStatus = worst;
                    mShiftPartsFromAnt = true;
                } else {
                    mShiftPartsFromAnt = false;
                }
            } catch (ex) {
            }
        }

        if (mBleMgr != null) {
            var hrLive = false;
            if (Toybox.Activity has :getActivityInfo) {
                try {
                    var act = Activity.getActivityInfo();
                    if (act != null && act.currentHeartRate != null) {
                        hrLive = true;
                    }
                } catch (exHr) {}
            }
            mBleMgr.setHrDataLive(hrLive);
            mBleMgr.setPmAntConnected(mBikePowerListener != null && mBikePowerListener.isConnected());
            pushLiveHrmAntTarget(hrLive);
            maybeFeedAntIdsToBleMgr();
            if (mShiftPartsFromAnt) {
                var di2Stored = mBleMgr.getStoredDi2Name();
                var di2Current = mBleMgr.getDi2DeviceName();
                if (!di2Stored.equals("") || !di2Current.equals("")) {
                    mBleMgr.setDi2NotNeeded();
                }
            }
            try {
                mBleMgr.compute();
            } catch (exBle) {}
            var di2Pct = mBleMgr.getDi2BatteryPercent();
            if (di2Pct >= 0 && !mShiftPartsFromAnt) {
                setShiftPart(0, di2Pct.format("%d") + "%");
                mShiftPartsCount = 1;
                if (di2Pct <= 5) {
                    mShiftWorstStatus = AntPlus.BATT_STATUS_CRITICAL;
                } else if (di2Pct <= 20) {
                    mShiftWorstStatus = AntPlus.BATT_STATUS_LOW;
                } else if (di2Pct <= 50) {
                    mShiftWorstStatus = AntPlus.BATT_STATUS_OK;
                } else {
                    mShiftWorstStatus = AntPlus.BATT_STATUS_GOOD;
                }
            }
        }

        if (mBleMgr != null) {
            var hrmPct = mBleMgr.getHrmBatteryPercent();
            mHrBatteryPercent = hrmPct;
            var pmBlePct = mBleMgr.getPmBatteryPercent();
            mPmBleBatteryPercent = pmBlePct;
        }

        if (mBikeRadar != null && mBikeRadarListener != null && mBikeRadarListener.isConnected()) {
            try {
                var radar = mBikeRadar as AntPlus.BikeRadar;
                var radarIds = radar.getComponentIdentifiers();
                if (radarIds != null && radarIds.size() > 0) {
                    var batt = radar.getBatteryStatus(radarIds[0]);
                    if (batt != null && batt.batteryStatus != null) {
                        mVariaBatteryStatus = batt.batteryStatus;
                        if (batt.batteryVoltage != null) {
                            mVariaVoltage = batt.batteryVoltage as Float;
                        }
                    }
                }
                if (mVariaBatteryStatus == AntPlus.BATT_STATUS_INVALID) {
                    var batt = radar.getBatteryStatus(0);
                    if (batt != null && batt.batteryStatus != null) {
                        mVariaBatteryStatus = batt.batteryStatus;
                        if (batt.batteryVoltage != null) {
                            mVariaVoltage = batt.batteryVoltage as Float;
                        }
                    }
                }
            } catch (ex) {
            }
        }

        if (mLightNetwork != null && mLightNetworkListener != null && mLightNetworkListener.isNetworkFormed()) {
            var ln = mLightNetwork as AntPlus.LightNetwork;
            if (mVariaBatteryStatus == AntPlus.BATT_STATUS_INVALID && mLightNetworkListener.hasRearLight()) {
                var rearIdx = mLightNetworkListener.getRearIndex();
                if (rearIdx != null) {
                    try {
                        var batt = ln.getBatteryStatus(rearIdx);
                        if (batt != null && batt.batteryStatus != null) {
                            mVariaBatteryStatus = batt.batteryStatus;
                            if (batt.batteryVoltage != null) {
                                mVariaVoltage = batt.batteryVoltage as Float;
                            }
                        }
                    } catch (ex) {
                    }
                }
            }
            var frontIdx = mLightNetworkListener.getFrontIndex();
            if (frontIdx != null) {
                try {
                    var batt = ln.getBatteryStatus(frontIdx);
                    if (batt != null && batt.batteryStatus != null) {
                        mFrontLightBatteryStatus = batt.batteryStatus;
                        if (batt.batteryVoltage != null) {
                            mFrontLightVoltage = batt.batteryVoltage as Float;
                        }
                    }
                } catch (ex) {
                }
            }
            if (mFrontLightBatteryStatus == AntPlus.BATT_STATUS_INVALID) {
                try {
                    var ids = ln.getComponentIdentifiers();
                    if (ids != null) {
                        var rearIdx = mLightNetworkListener.getRearIndex();
                        for (var i = 0; i < ids.size(); i++) {
                            if (rearIdx != null && ids[i] == rearIdx) {
                                continue;
                            }
                            if (frontIdx != null && ids[i] == frontIdx) {
                                continue;
                            }
                            var batt = ln.getBatteryStatus(ids[i]);
                            if (batt != null && batt.batteryStatus != null) {
                                mFrontLightBatteryStatus = batt.batteryStatus;
                                if (batt.batteryVoltage != null) {
                                    mFrontLightVoltage = batt.batteryVoltage as Float;
                                }
                                break;
                            }
                        }
                    }
                } catch (ex) {
                }
            }
        }

        var stats = System.getSystemStats();
        mDeviceBattery = stats.battery;
        if (stats has :charging) {
            mDeviceCharging = stats.charging;
        }
    }

    function onUpdate(dc as Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_WHITE);
        dc.clear();

        try {
            onUpdateInner(dc, width, height);
        } catch (ex) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_WHITE);
            dc.drawText(width / 2, height / 2, Graphics.FONT_SMALL, "Error", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function onUpdateInner(dc as Dc, width as Number, height as Number) as Void {

        // Reuse member row buffers
        mRowCount = 0;

        if (showPmBattery && debugMode) {
            var dbg = buildPmDebugText();
            addRow(pmPosition * 10, dbg, Graphics.COLOR_DK_BLUE);
        } else if (showPmBattery) {
            var pmLabel = "PM";
            if (mBleMgr != null) {
                var n = mBleMgr.getPreferredDisplayName(2);
                if (!n.equals("")) { pmLabel = n; }
            }
            if (mPmBleBatteryPercent >= 0) {
                var pmText = pmLabel + ": " + mPmBleBatteryPercent.format("%d") + "%";
                var pmColor = percentToColor(mPmBleBatteryPercent.toFloat());
                addRow(pmPosition * 10, pmText, pmColor);
            } else if (mBleMgr == null || mBleMgr.isPmBleExhausted()) {
                var hasDualBattery = (mPmRightBatteryStatus != AntPlus.BATT_STATUS_INVALID);
                if (hasDualBattery) {
                    var lPct = formatBatteryPct(mPmLeftBatteryStatus);
                    var rPct = formatBatteryPct(mPmRightBatteryStatus);
                    var lColor = batteryColor(mPmLeftBatteryStatus);
                    var rColor = batteryColor(mPmRightBatteryStatus);
                    var pmColor = worstColor(lColor, rColor);
                    var pmText = pmLabel + ": " + lPct + " | " + rPct;
                    addRow(pmPosition * 10, pmText, pmColor);
                } else if (mPmLeftBatteryStatus != AntPlus.BATT_STATUS_INVALID) {
                    var pctStr = formatBatteryPct(mPmLeftBatteryStatus);
                    var pmText = pmLabel + ": " + pctStr;
                    addRow(pmPosition * 10, pmText, batteryColor(mPmLeftBatteryStatus));
                } else {
                    addRow(pmPosition * 10, pmLabel + ": --", Graphics.COLOR_LT_GRAY);
                }
            } else {
                addRow(pmPosition * 10, pmLabel + ": --", Graphics.COLOR_LT_GRAY);
            }
        }

        if (showShiftingBattery) {
            if (debugMode) {
                var dbgRows = buildShiftDebugRows();
                for (var r = 0; r < dbgRows.size(); r++) {
                    addRow(shifterPosition * 10 + r, dbgRows[r] as String, Graphics.COLOR_DK_BLUE);
                }
            } else {
                var shiftLabel = "Shift";
                if (mBleMgr != null) {
                    var dn = mBleMgr.getPreferredDisplayName(0);
                    if (dn.equals("")) { dn = mBleMgr.getDi2DeviceName(); }
                    if (!dn.equals("")) { shiftLabel = "Shift(" + dn + ")"; }
                }
                var shiftText = shiftLabel + ": ";
                var shiftColor = batteryStatusToColor(mShiftWorstStatus);
                if (mShiftPartsCount > 0) {
                    for (var i = 0; i < mShiftPartsCount; i++) {
                        if (i > 0) { shiftText = shiftText + "/"; }
                        shiftText = shiftText + mShiftDisplayParts[i];
                    }
                } else if (mShiftingListener != null && mShiftingListener.getRawBatteryCount() > 0) {
                    var parts = buildRawShiftParts(mShiftingListener.getRawBatteryCount(),
                        mShiftingListener);
                    shiftText = shiftText + parts;
                    shiftColor = batteryStatusToColor(mShiftingListener.getBatteryStatus());
                } else if (mShiftingListener != null && mShiftingListener.getBatteryStatus() != AntPlus.BATT_STATUS_INVALID) {
                    shiftText = shiftText + batteryStatusToString(mShiftingListener.getBatteryStatus());
                    shiftColor = batteryStatusToColor(mShiftingListener.getBatteryStatus());
                } else {
                    shiftText = shiftText + "--";
                }
                addRow(shifterPosition * 10 + 1, shiftText, shiftColor);
            }
        }

        if (showVaria) {
            if (debugMode) {
                var dbg = buildRearDebugText();
                addRow(rearPosition * 10 + 3, dbg, Graphics.COLOR_DK_BLUE);
            } else {
                var variaPct = formatBatteryPct(mVariaBatteryStatus);
                var variaText = "R. Light: " + variaPct;
                if (mBikeRadarListener != null && mBikeRadarListener.hasThreat()) {
                    variaText = variaText + "  " + mBikeRadarListener.getStatus();
                }
                if (showVariaMode && mLightNetworkListener != null) {
                    var mode = mLightNetworkListener.getRearLightMode();
                    if (!mode.equals("--")) {
                        variaText = variaText + "  " + mode;
                    }
                }
                addRow(rearPosition * 10 + 3, variaText, batteryStatusToColor(mVariaBatteryStatus));
            }
        }

        if (showFrontLight) {
            if (debugMode) {
                var dbg = buildFrontDebugText();
                addRow(frontPosition * 10 + 4, dbg, Graphics.COLOR_DK_BLUE);
            } else {
                var frontPct = formatBatteryPct(mFrontLightBatteryStatus);
                var frontText = "F. Light: " + frontPct;
                if (showFrontLightMode && mLightNetworkListener != null) {
                    var fMode = mLightNetworkListener.getFrontLightMode();
                    if (!fMode.equals("--")) {
                        frontText = frontText + "  " + fMode;
                    }
                }
                addRow(frontPosition * 10 + 4, frontText, batteryStatusToColor(mFrontLightBatteryStatus));
            }
        }

        if (showHrm && !debugMode) {
            // In debug, HRM BLE state is on the Shift block's "HRM:" row only
            var hrmLabel = "HR";
            if (mBleMgr != null) {
                var n = mBleMgr.getPreferredDisplayName(1);
                if (!n.equals("")) { hrmLabel = n; }
            }
            var hrmText = hrmLabel + ": --";
            var hrmColor = Graphics.COLOR_LT_GRAY as Graphics.ColorValue;
            if (mHrBatteryPercent >= 0) {
                var hrmPctVal = mHrBatteryPercent.toFloat();
                hrmText = hrmLabel + ": " + mHrBatteryPercent.format("%d") + "%";
                hrmColor = percentToColor(hrmPctVal);
            }
            addRow(hrmPosition * 10 + 5, hrmText, hrmColor);
        }

        if (showDeviceBattery) {
            var devText = "Device: " + mDeviceBattery.format("%.0f") + "%";
            if (mDeviceCharging) {
                devText = devText + "+";
            }
            addRow(devicePosition * 10 + 6, devText, deviceBatteryColor(mDeviceBattery));
        }

        if (showCadence) {
            if (debugMode) {
                var dbg = buildCadenceDebugText();
                addRow(cadencePosition * 10 + 7, dbg, Graphics.COLOR_DK_BLUE);
            } else {
                var cadText = "Cadence: --";
                var cadColor = Graphics.COLOR_LT_GRAY as Graphics.ColorValue;
                if (mCadenceBatteryStatus != AntPlus.BATT_STATUS_INVALID) {
                    var cPct = batteryStatusToPercent(mCadenceBatteryStatus);
                    if (cPct >= 0.0f) {
                        cadText = "Cadence: " + cPct.format("%d") + "%";
                        cadColor = percentToColor(cPct);
                    }
                }
                addRow(cadencePosition * 10 + 7, cadText, cadColor);
            }
        }

        if (showSpeed) {
            if (debugMode) {
                var dbg = buildSpeedDebugText();
                addRow(speedPosition * 10 + 8, dbg, Graphics.COLOR_DK_BLUE);
            } else {
                var spdText = "Speed: --";
                var spdColor = Graphics.COLOR_LT_GRAY as Graphics.ColorValue;
                if (mSpeedBatteryStatus != AntPlus.BATT_STATUS_INVALID) {
                    var sPct = batteryStatusToPercent(mSpeedBatteryStatus);
                    if (sPct >= 0.0f) {
                        spdText = "Speed: " + sPct.format("%d") + "%";
                        spdColor = percentToColor(sPct);
                    }
                }
                addRow(speedPosition * 10 + 8, spdText, spdColor);
            }
        }

        // Insertion sort by sortKeys (active prefix only)
        for (var i = 1; i < mRowCount; i++) {
            var key = mRowSortKeys[i];
            var txt = mRowTexts[i];
            var col = mRowColors[i];
            var j = i - 1;
            while (j >= 0 && mRowSortKeys[j] > key) {
                mRowSortKeys[j + 1] = mRowSortKeys[j];
                mRowTexts[j + 1] = mRowTexts[j];
                mRowColors[j + 1] = mRowColors[j];
                j--;
            }
            mRowSortKeys[j + 1] = key;
            mRowTexts[j + 1] = txt;
            mRowColors[j + 1] = col;
        }

        // Draw title
        var titleFont = (width >= 400) ? Graphics.FONT_MEDIUM : Graphics.FONT_SMALL;
        var titleHeight = dc.getFontHeight(titleFont);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, 2, titleFont, titleText, Graphics.TEXT_JUSTIFY_CENTER);

        if (mRowCount > 0) {
            var availableHeight = height - titleHeight - 4;
            var rowHeight = availableHeight / mRowCount;
            var fontIdx = pickFontIndex(rowHeight, width);
            var font = mFontLadder[fontIdx];
            var fontHeight = dc.getFontHeight(font);
            var startY = titleHeight + 4;

            for (var i = 0; i < mRowCount; i++) {
                var y = startY + (i * rowHeight);
                var bandHeight = (i == mRowCount - 1) ? (height - y) : rowHeight;
                var bandColor = mRowColors[i];
                dc.setColor(bandColor, bandColor);
                dc.fillRectangle(0, y, width, bandHeight);

                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                if (fontIdx == 5) {
                    var textY = y + (bandHeight - fontHeight) / 2;
                    dc.drawText(width / 2, textY, font, mRowTexts[i], Graphics.TEXT_JUSTIFY_CENTER);
                } else {
                    dc.drawText(
                        width / 2,
                        y + bandHeight / 2,
                        font,
                        mRowTexts[i],
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
                    );
                }
            }
        }
    }

    // Throttle full identity rebuild; cheap live ANT ID pushes between full feeds.
    hidden function maybeFeedAntIdsToBleMgr() as Void {
        if (mBleMgr == null) { return; }

        var di2Conn = mShiftingListener != null && mShiftingListener.isConnected();
        var pmConn = mBikePowerListener != null && mBikePowerListener.isConnected();
        if (di2Conn != mLastDi2AntConn || pmConn != mLastPmAntConn) {
            mLastDi2AntConn = di2Conn;
            mLastPmAntConn = pmConn;
            mNeedFullIdentityFeed = true;
        }

        pushLiveAntIdsCheap();

        var doFull = mNeedFullIdentityFeed;
        if (!doFull && mBleMgr.needsIdentityRefresh()) {
            mFeedIdentityTick = mFeedIdentityTick + 1;
            if (mFeedIdentityTick >= FEED_IDENTITY_INTERVAL) {
                doFull = true;
            }
        } else if (!mBleMgr.needsIdentityRefresh()) {
            mFeedIdentityTick = 0;
        }

        if (doFull) {
            feedAntIdsToBleMgr();
            mNeedFullIdentityFeed = false;
            mFeedIdentityTick = 0;
        }
    }

    // Live HRM ANT serial when exactly one enabled strap — disambiguates BLE scan among registered HRMs.
    hidden function pushLiveHrmAntTarget(hrLive as Boolean) as Void {
        if (mBleMgr == null) { return; }
        if (!hrLive) {
            mBleMgr.setLiveAntTarget(1, 0);
            mLastFedHrmAntId = 0;
            return;
        }
        var antId = 0;
        var enabledWithId = 0;
        try {
            var it = Sensor.getRegisteredSensors(Sensor.SENSOR_HEARTRATE);
            var info = it.next();
            while (info != null) {
                var si = info as Sensor.SensorInfo;
                if (si.enabled) {
                    var candidateId = 0;
                    var data = si.data;
                    if (data != null) {
                        var antSn = data[:antSerialNumber];
                        if (antSn instanceof Number && (antSn as Number) > 0) {
                            candidateId = antSn as Number;
                        }
                    }
                    if (candidateId > 0) {
                        enabledWithId++;
                        antId = candidateId;
                    }
                }
                info = it.next();
            }
        } catch (ex) {}
        if (enabledWithId != 1) {
            antId = 0;
        }
        if (antId > 0 && antId != mLastFedHrmAntId) {
            mBleMgr.addCandidateId(1, antId);
            mLastFedHrmAntId = antId;
        }
        mBleMgr.setLiveAntTarget(1, antId);
    }

    // Push live AntPlus deviceNumber/serial only when values change (no clearCandidates).
    hidden function pushLiveAntIdsCheap() as Void {
        if (mBleMgr == null) { return; }

        if (mShifting != null) {
            try {
                var shiftSt = mShifting.getDeviceState();
                if (shiftSt != null && shiftSt.deviceNumber != null) {
                    var dn = shiftSt.deviceNumber as Number;
                    if (dn > 0 && dn != mLastFedDi2Num) {
                        mBleMgr.addCandidateId(0, dn);
                        mLastFedDi2Num = dn;
                    }
                }
            } catch (ex) {}
            if (mShiftingListener != null) {
                var di2Num = mShiftingListener.getDeviceNumber();
                if (di2Num > 0 && di2Num != mLastFedDi2Num) {
                    mBleMgr.addCandidateId(0, di2Num);
                    mLastFedDi2Num = di2Num;
                }
                var di2Serial = mShiftingListener.getSerialNumber();
                if (di2Serial > 0 && di2Serial != mLastFedDi2Serial) {
                    mBleMgr.addCandidateId(0, di2Serial);
                    mLastFedDi2Serial = di2Serial;
                }
            }
        }

        var pmLiveTarget = 0;
        var pmConnected = mBikePowerListener != null && mBikePowerListener.isConnected();
        if (mBikePower != null) {
            try {
                var st = mBikePower.getDeviceState();
                if (st != null && st.deviceNumber != null) {
                    var pmDn = st.deviceNumber as Number;
                    if (pmDn > 0 && pmDn != mLastFedPmNum) {
                        mBleMgr.addCandidateId(2, pmDn);
                        mLastFedPmNum = pmDn;
                    }
                    if (pmConnected && pmDn > 0) {
                        pmLiveTarget = pmDn;
                    }
                }
            } catch (ex) {}
            if (mBikePowerListener != null) {
                var pmNum = mBikePowerListener.getDeviceNumber();
                if (pmNum > 0 && pmNum != mLastFedPmNum) {
                    mBleMgr.addCandidateId(2, pmNum);
                    mLastFedPmNum = pmNum;
                }
                if (pmConnected && pmLiveTarget <= 0 && pmNum > 0) {
                    pmLiveTarget = pmNum;
                }
            }
            try {
                var bp = mBikePower as AntPlus.BikePower;
                var pIds = bp.getComponentIdentifiers();
                if (pIds != null && pIds.size() > 0) {
                    var pmProd = bp.getProductInfo(pIds[0]);
                    if (pmProd != null && pmProd.serial != null) {
                        var pmSer = pmProd.serial as Number;
                        if (pmSer > 0 && pmSer != mLastFedPmSerial) {
                            mBleMgr.addCandidateId(2, pmSer);
                            mLastFedPmSerial = pmSer;
                        }
                    }
                }
            } catch (ex) {}
        }
        if (pmConnected && pmLiveTarget <= 0 && mBikePowerListener != null) {
            var pmNumFallback = mBikePowerListener.getDeviceNumber();
            if (pmNumFallback > 0) {
                pmLiveTarget = pmNumFallback;
            }
        }
        mBleMgr.setLiveAntTarget(2, pmLiveTarget);
    }

    // Push ALL Garmin-registered sensors + live ANT IDs into BLE manager.
    // Match uses IDs only; Garmin names are display-only (user can rename them).
    hidden function feedAntIdsToBleMgr() as Void {
        if (mBleMgr == null) { return; }

        mBleMgr.clearCandidates(0);
        mBleMgr.clearCandidates(1);
        mBleMgr.clearCandidates(2);

        // Di2 = slot 0 — no Sensor.SENSOR_* type; always pull live AntPlus IDs
        if (mShifting != null) {
            try {
                var shiftSt = mShifting.getDeviceState();
                if (shiftSt != null && shiftSt.deviceNumber != null && (shiftSt.deviceNumber as Number) > 0) {
                    mLastFedDi2Num = shiftSt.deviceNumber as Number;
                    mBleMgr.addCandidateId(0, mLastFedDi2Num);
                }
            } catch (ex) {}
            if (mShiftingListener != null) {
                var di2Num = mShiftingListener.getDeviceNumber();
                if (di2Num > 0) {
                    mLastFedDi2Num = di2Num;
                    mBleMgr.addCandidateId(0, di2Num);
                }
                var di2Serial = mShiftingListener.getSerialNumber();
                if (di2Serial > 0) {
                    mLastFedDi2Serial = di2Serial;
                    mBleMgr.addCandidateId(0, di2Serial);
                }
            }
            try {
                var shift = mShifting as AntPlus.Shifting;
                var sIds = shift.getComponentIdentifiers();
                if (sIds != null) {
                    for (var si = 0; si < sIds.size(); si++) {
                        var prodInfo = shift.getProductInfo(sIds[si]);
                        if (prodInfo != null && prodInfo.serial != null && (prodInfo.serial as Number) > 0) {
                            mBleMgr.addCandidateId(0, prodInfo.serial as Number);
                        }
                    }
                }
            } catch (ex) {}
        }
        feedDi2RegisteredSensors();

        // PM = slot 2 — live AntPlus
        if (mBikePower != null) {
            try {
                var st = mBikePower.getDeviceState();
                if (st != null && st.deviceNumber != null && (st.deviceNumber as Number) > 0) {
                    mLastFedPmNum = st.deviceNumber as Number;
                    mBleMgr.addCandidateId(2, mLastFedPmNum);
                }
            } catch (ex) {}
            if (mBikePowerListener != null) {
                var pmNum = mBikePowerListener.getDeviceNumber();
                if (pmNum > 0) {
                    mLastFedPmNum = pmNum;
                    mBleMgr.addCandidateId(2, pmNum);
                }
            }
            try {
                var bp = mBikePower as AntPlus.BikePower;
                var pIds = bp.getComponentIdentifiers();
                if (pIds != null && pIds.size() > 0) {
                    var pmProd = bp.getProductInfo(pIds[0]);
                    if (pmProd != null && pmProd.serial != null) {
                        mLastFedPmSerial = pmProd.serial as Number;
                        mBleMgr.addCandidateId(2, mLastFedPmSerial);
                    }
                }
            } catch (ex) {}
        }

        // All Garmin-stored sensors in each category (names for display, IDs for match).
        // Registered-sensor IDs only — never pairDevice from :bleScanResult (stale = crash).
        feedAllRegisteredSensors(1, Sensor.SENSOR_HEARTRATE);
        feedAllRegisteredSensors(2, Sensor.SENSOR_BIKEPOWER);
    }

    hidden function feedAllRegisteredSensors(slot as Number, sensorType as Sensor.SensorType) as Void {
        if (mBleMgr == null) { return; }
        try {
            var it = Sensor.getRegisteredSensors(sensorType);
            var info = it.next();
            while (info != null) {
                var si = info as Sensor.SensorInfo;
                // Only enabled sensors (same flag already used for BLE scan pair)
                if (si.enabled) {
                    var antId = 0;
                    var data = si.data;
                    if (data != null) {
                        var antSn = data[:antSerialNumber];
                        if (antSn instanceof Number && (antSn as Number) > 0) {
                            antId = antSn as Number;
                            mBleMgr.addCandidateId(slot, antId);
                        }
                        var bleAddr = data[:bleAddress];
                        if (bleAddr instanceof ByteArray) {
                            mBleMgr.addBleAddress(slot, bleAddr as ByteArray);
                        }
                    }
                    if (si.name != null && !si.name.equals("")) {
                        // Name for display only — BLE match uses antId, never this string
                        mBleMgr.addGarminSensor(slot, si.name, antId);
                    }
                }
                info = it.next();
            }
        } catch (ex) {}
    }

    // Shifting has no SENSOR_* type — scan all registered sensors for Di2-like entries.
    // Prefer data[:bleAddress] / :bleScanResult when present (see SensorInfo docs).
    // Cache IDs/names after first walk; re-walk while identity still needs refresh
    // so tryPairRegisteredScan / MAC can still run.
    hidden function feedDi2RegisteredSensors() as Void {
        if (mBleMgr == null) { return; }

        if (mDi2RegCacheValid && !mBleMgr.needsIdentityRefresh()) {
            applyCachedDi2Registered();
            return;
        }

        mCachedDi2RegCount = 0;
        try {
            var it = Sensor.getRegisteredSensors(null);
            var info = it.next();
            while (info != null) {
                var si = info as Sensor.SensorInfo;
                if (si.enabled) {
                    var nm = (si.name != null) ? si.name : "";
                    if (nameLooksLikeDi2(nm)) {
                        var antId = 0;
                        var data = si.data;
                        if (data != null) {
                            var antSn = data[:antSerialNumber];
                            if (antSn instanceof Number && (antSn as Number) > 0) {
                                antId = antSn as Number;
                                mBleMgr.addCandidateId(0, antId);
                            }
                            var bleAddr = data[:bleAddress];
                            if (bleAddr instanceof ByteArray) {
                                mBleMgr.addBleAddress(0, bleAddr as ByteArray);
                            }
                        }
                        if (!nm.equals("")) {
                            mBleMgr.addGarminSensor(0, nm, antId);
                        }
                        if (mCachedDi2RegCount < mCachedDi2RegIds.size()) {
                            mCachedDi2RegIds[mCachedDi2RegCount] = antId;
                            mCachedDi2RegNames[mCachedDi2RegCount] = nm;
                            mCachedDi2RegCount = mCachedDi2RegCount + 1;
                        }
                    }
                }
                info = it.next();
            }
            mDi2RegCacheValid = true;
        } catch (ex) {}
    }

    hidden function applyCachedDi2Registered() as Void {
        if (mBleMgr == null) { return; }
        for (var i = 0; i < mCachedDi2RegCount; i++) {
            var id = mCachedDi2RegIds[i];
            if (id > 0) {
                mBleMgr.addCandidateId(0, id);
            }
            var nm = mCachedDi2RegNames[i];
            if (nm != null && !nm.equals("")) {
                mBleMgr.addGarminSensor(0, nm, id);
            }
        }
    }

    hidden function nameLooksLikeDi2(name as String) as Boolean {
        if (name == null || name.equals("")) { return false; }
        // Avoid String.toLower (API 4.0+); minApiLevel is 3.3.0
        if (name.find("di2") != null || name.find("Di2") != null || name.find("DI2") != null) { return true; }
        if (name.find("shimano") != null || name.find("Shimano") != null) { return true; }
        if (name.find("shift") != null || name.find("Shift") != null) { return true; }
        return false;
    }

    // A: Garmin registered names (stand in for candidate identity) | P: BLE pairing name
    // No C: — A: already lists the sensors whose ANT IDs we feed for match.
    hidden function formatBleDebugSuffix(slot as Number, bleName as String) as String {
        if (mBleMgr == null) { return ""; }
        var s = "";
        var gNames = mBleMgr.getGarminNamesDebug(slot);
        if (!gNames.equals("")) {
            s = s + " A:" + gNames;
        }
        if (!bleName.equals("")) {
            s = s + " P:" + bleName;
        }
        return s;
    }

    hidden function buildPmDebugText() as String {
        var text = "PM:";
        if (mBikePower == null) {
            text = text + " Off";
        } else {
            text = text + (mBikePowerListener != null && mBikePowerListener.isConnected() ? " Conn" : " Search");
            try {
                var bp = mBikePower as AntPlus.BikePower;
                var ids = bp.getComponentIdentifiers();
                if (ids != null && ids.size() > 0) {
                    text = text + " x" + ids.size();
                    for (var i = 0; i < ids.size() && i < 2; i++) {
                        var batt = bp.getBatteryStatus(ids[i]);
                        if (batt != null && batt.batteryStatus != null) {
                            text = text + " " + batteryStatusToDbg(batt.batteryStatus);
                            if (batt.batteryVoltage != null) {
                                text = text + "/" + (batt.batteryVoltage as Float).format("%.1f") + "V";
                            }
                        } else {
                            text = text + " ?";
                        }
                    }
                } else {
                    text = text + " NoIds";
                }
            } catch (ex) {
                text = text + " Err";
            }
        }
        var ls = batteryStatusToDbg(mPmLeftBatteryStatus);
        if (mPmLeftVoltage != null) {
            ls = ls + "/" + (mPmLeftVoltage as Float).format("%.1f") + "V";
        }
        text = text + " L:" + ls;
        var rs = batteryStatusToDbg(mPmRightBatteryStatus);
        if (mPmRightVoltage != null) {
            rs = rs + "/" + (mPmRightVoltage as Float).format("%.1f") + "V";
        }
        text = text + " R:" + rs;
        return text;
    }

    hidden function buildShiftDebugRows() as Array {
        var rows = [] as Array;

        var antText = "ANT:";
        if (mShifting == null) {
            antText = antText + " Off";
        } else {
            antText = antText + (mShiftingListener != null && mShiftingListener.isConnected() ? " Conn" : " Search");
            try {
                var shift = mShifting as AntPlus.Shifting;
                var sIds = shift.getComponentIdentifiers();
                if (sIds != null && sIds.size() > 0) {
                    antText = antText + " x" + sIds.size();
                } else {
                    antText = antText + " NoIds";
                }
            } catch (ex) {}
            if (mShiftingListener != null) {
                antText = antText + " rx" + mShiftingListener.getRawMsgCount();
                var antDn = mShiftingListener.getDeviceNumber();
                if (antDn > 0) {
                    antText = antText + " #" + antDn.toString();
                }
                var antSn = mShiftingListener.getSerialNumber();
                if (antSn > 0) {
                    antText = antText + " sn" + antSn.toString();
                }
            }
            try {
                var st = mShifting.getDeviceState();
                if (st != null && st.deviceNumber != null && (st.deviceNumber as Number) > 0) {
                    antText = antText + " d#" + (st.deviceNumber as Number).toString();
                }
            } catch (ex2) {}
        }
        rows.add(antText);

        if (mBleMgr != null) {
            var bleText = "BLE:" + mBleMgr.getMgrStateString() + " " + mBleMgr.getPhaseString();
            bleText = bleText + " d" + mBleMgr.getScanDeviceCount();
            var bleErr = mBleMgr.getErrorMsg();
            if (!bleErr.equals("")) {
                bleText = bleText + " E:" + bleErr;
            }
            rows.add(bleText);
            var di2Pct = mBleMgr.getDi2BatteryPercent();
            var di2Row = "Di2:" + mBleMgr.getDevStateString(0) + (di2Pct >= 0 ? " " + di2Pct + "%" : " --");
            di2Row = di2Row + formatBleDebugSuffix(0, mBleMgr.getDi2PairDebugLabel());
            var di2Ids = mBleMgr.getAntMatchDebug(0);
            if (!di2Ids.equals("")) {
                di2Row = di2Row + " " + di2Ids;
            }
            rows.add(di2Row);
            var pmPct = mBleMgr.getPmBatteryPercent();
            var pmRow = "PM:" + mBleMgr.getDevStateString(2) + (pmPct >= 0 ? " " + pmPct + "%" : " --");
            pmRow = pmRow + formatBleDebugSuffix(2, mBleMgr.getPmDeviceName());
            rows.add(pmRow);
            var hrmPct = mBleMgr.getHrmBatteryPercent();
            var hrmRow = "HRM:" + mBleMgr.getHrmStateString() + (hrmPct >= 0 ? " " + hrmPct + "%" : " --");
            hrmRow = hrmRow + formatBleDebugSuffix(1, mBleMgr.getHrmDeviceName());
            rows.add(hrmRow);
        }

        return rows;
    }

    hidden function buildRearDebugText() as String {
        var text = "R.Light:";
        if (mBikeRadar == null && mLightNetwork == null) {
            return text + " Off";
        }
        if (mBikeRadar != null) {
            text = text + " Rdr:" + (mBikeRadarListener != null && mBikeRadarListener.isConnected() ? "Conn" : "Search");
        }
        if (mLightNetwork != null) {
            text = text + " LN:" + (mLightNetworkListener != null && mLightNetworkListener.isNetworkFormed() ? "Formed" : "Search");
            if (mLightNetworkListener != null && mLightNetworkListener.hasRearLight()) {
                text = text + " rIdx:" + (mLightNetworkListener.getRearIndex() != null ? mLightNetworkListener.getRearIndex().format("%d") : "?");
            }
        }
        text = text + " " + batteryStatusToDbg(mVariaBatteryStatus);
        if (mVariaVoltage != null) {
            text = text + "/" + (mVariaVoltage as Float).format("%.1f") + "V";
        }
        return text;
    }

    hidden function buildFrontDebugText() as String {
        var text = "F.Light:";
        if (mLightNetwork == null) {
            return text + " Off";
        }
        text = text + " LN:" + (mLightNetworkListener != null && mLightNetworkListener.isNetworkFormed() ? "Formed" : "Search");
        if (mLightNetworkListener != null && mLightNetworkListener.hasFrontLight()) {
            text = text + " fIdx:" + (mLightNetworkListener.getFrontIndex() != null ? mLightNetworkListener.getFrontIndex().format("%d") : "?");
        }
        if (mLightNetworkListener != null) {
            text = text + " m:" + mLightNetworkListener.getFrontLightMode();
        }
        text = text + " " + batteryStatusToDbg(mFrontLightBatteryStatus);
        if (mFrontLightVoltage != null) {
            text = text + "/" + (mFrontLightVoltage as Float).format("%.1f") + "V";
        }
        return text;
    }

    hidden function buildCadenceDebugText() as String {
        var text = "Cad:";
        if (mBikeCadence == null) {
            return text + " Off";
        }
        text = text + (mBikeCadenceListener != null && mBikeCadenceListener.isConnected() ? " Conn" : " Search");
        try {
            var cad = mBikeCadence as AntPlus.BikeCadence;
            var ids = cad.getComponentIdentifiers();
            text = text + " id" + (ids != null ? ids.size() : 0);
        } catch (ex) { text = text + " id?"; }
        text = text + " " + batteryStatusToDbg(mCadenceBatteryStatus);
        if (mCadenceVoltage != null) {
            text = text + "/" + (mCadenceVoltage as Float).format("%.2f") + "V";
        }
        return text;
    }

    hidden function buildSpeedDebugText() as String {
        var text = "Spd:";
        if (mBikeSpeed == null) {
            return text + " Off";
        }
        text = text + (mBikeSpeedListener != null && mBikeSpeedListener.isConnected() ? " Conn" : " Search");
        try {
            var spd = mBikeSpeed as AntPlus.BikeSpeed;
            var ids = spd.getComponentIdentifiers();
            text = text + " id" + (ids != null ? ids.size() : 0);
        } catch (ex) { text = text + " id?"; }
        text = text + " " + batteryStatusToDbg(mSpeedBatteryStatus);
        if (mSpeedVoltage != null) {
            text = text + "/" + (mSpeedVoltage as Float).format("%.2f") + "V";
        }
        return text;
    }

    hidden function rawStatusToAntPlus(raw as Number) as AntPlus.BatteryStatusValue {
        switch (raw) {
            case 1: return AntPlus.BATT_STATUS_NEW;
            case 2: return AntPlus.BATT_STATUS_GOOD;
            case 3: return AntPlus.BATT_STATUS_OK;
            case 4: return AntPlus.BATT_STATUS_LOW;
            case 5: return AntPlus.BATT_STATUS_CRITICAL;
            default: return AntPlus.BATT_STATUS_INVALID;
        }
    }

    hidden function batteryStatusToDbg(status as AntPlus.BatteryStatusValue) as String {
        switch (status) {
            case AntPlus.BATT_STATUS_NEW: return "N";
            case AntPlus.BATT_STATUS_GOOD: return "G";
            case AntPlus.BATT_STATUS_OK: return "K";
            case AntPlus.BATT_STATUS_LOW: return "L";
            case AntPlus.BATT_STATUS_CRITICAL: return "!";
            case AntPlus.BATT_STATUS_INVALID: return "?";
            default: return "?";
        }
    }

    hidden function setShiftPart(idx as Number, text as String) as Void {
        if (idx < mShiftDisplayParts.size()) {
            mShiftDisplayParts[idx] = text;
        } else {
            mShiftDisplayParts.add(text);
        }
    }

    hidden function addRow(key as Number, text as String, color as Graphics.ColorValue) as Void {
        if (mRowCount < mRowSortKeys.size()) {
            mRowSortKeys[mRowCount] = key;
            mRowTexts[mRowCount] = text;
            mRowColors[mRowCount] = color;
        } else {
            mRowSortKeys.add(key);
            mRowTexts.add(text);
            mRowColors.add(color);
        }
        mRowCount = mRowCount + 1;
    }

    hidden function pickFontIndex(rowHeight as Number, screenWidth as Number) as Number {
        var idx = FontZoom.rowBaseline(rowHeight, screenWidth);
        var maxIdx = (screenWidth >= 400) ? 5 : 4;
        return FontZoom.rowIndex(idx, textZoom, maxIdx);
    }

    hidden function shiftComponentLabel(id as Number) as String {
        switch (id) {
            case 0: return "S";
            case 1: return "FD";
            case 2: return "RD";
            case 3: return "L";
            case 4: return "R";
            case 5: return "S";
            case 6: return "L";
            case 7: return "R";
            case 8: return "E";
            default: return id.format("%d");
        }
    }

    hidden function shiftBatteryIdLabel(battId as Number, total as Number) as String {
        if (total <= 1) { return ""; }
        switch (battId) {
            case 0: return "M";
            case 1: return "L";
            case 2: return "R";
            default: return battId.format("%d");
        }
    }

    hidden function buildRawShiftParts(count as Number, listener as MyShiftingListener) as String {
        var text = "";
        var total = listener.getRawBatteryTotal();
        for (var i = 0; i < count && i < 4; i++) {
            var v = listener.getRawBatteryVoltage(i);
            var s = listener.getRawBatteryStatus(i);
            if (v < 0.5f && s < 0) { continue; }
            if (!text.equals("")) { text = text + "/"; }
            var label = shiftBatteryIdLabel(i, total);
            text = text + label;
            if (s >= 0) {
                text = text + batteryStatusToString(rawStatusToAntPlus(s));
            } else if (v > 0.5f) {
                text = text + v.format("%.1f") + "V";
            }
        }
        if (text.equals("")) { text = "--"; }
        return text;
    }

    hidden function batteryStatusSeverity(status as AntPlus.BatteryStatusValue) as Number {
        switch (status) {
            case AntPlus.BATT_STATUS_CRITICAL: return 5;
            case AntPlus.BATT_STATUS_LOW: return 4;
            case AntPlus.BATT_STATUS_OK: return 3;
            case AntPlus.BATT_STATUS_GOOD: return 2;
            case AntPlus.BATT_STATUS_NEW: return 1;
            default: return 0;
        }
    }

    hidden function worstBatteryStatus(left as AntPlus.BatteryStatusValue, right as AntPlus.BatteryStatusValue) as AntPlus.BatteryStatusValue {
        if (batteryStatusSeverity(left) >= batteryStatusSeverity(right)) {
            return left;
        }
        return right;
    }

    hidden function batteryStatusToString(status as AntPlus.BatteryStatusValue) as String {
        switch (status) {
            case AntPlus.BATT_STATUS_NEW: return "100%";
            case AntPlus.BATT_STATUS_GOOD: return "75%";
            case AntPlus.BATT_STATUS_OK: return "50%";
            case AntPlus.BATT_STATUS_LOW: return "25%";
            case AntPlus.BATT_STATUS_CRITICAL: return "10%";
            case AntPlus.BATT_STATUS_INVALID: return "--";
            default: return "--";
        }
    }

    hidden function batteryStatusToColor(status as AntPlus.BatteryStatusValue) as Graphics.ColorValue {
        switch (status) {
            case AntPlus.BATT_STATUS_NEW: return Graphics.COLOR_DK_GREEN;
            case AntPlus.BATT_STATUS_GOOD: return Graphics.COLOR_DK_GREEN;
            case AntPlus.BATT_STATUS_OK: return Graphics.COLOR_YELLOW;
            case AntPlus.BATT_STATUS_LOW: return Graphics.COLOR_ORANGE;
            case AntPlus.BATT_STATUS_CRITICAL: return Graphics.COLOR_RED;
            case AntPlus.BATT_STATUS_INVALID: return Graphics.COLOR_LT_GRAY;
            default: return Graphics.COLOR_LT_GRAY;
        }
    }

    hidden function percentToColor(pct as Float) as Graphics.ColorValue {
        if (pct >= 75) { return Graphics.COLOR_DK_GREEN; }
        if (pct >= 50) { return Graphics.COLOR_YELLOW; }
        if (pct >= 25) { return Graphics.COLOR_ORANGE; }
        return Graphics.COLOR_RED;
    }

    hidden function batteryColor(status as AntPlus.BatteryStatusValue) as Graphics.ColorValue {
        return batteryStatusToColor(status);
    }

    hidden function colorSeverity(color as Graphics.ColorValue) as Number {
        if (color == Graphics.COLOR_RED) { return 4; }
        if (color == Graphics.COLOR_ORANGE) { return 3; }
        if (color == Graphics.COLOR_YELLOW) { return 2; }
        if (color == Graphics.COLOR_DK_GREEN) { return 1; }
        return 0;
    }

    hidden function worstColor(a as Graphics.ColorValue, b as Graphics.ColorValue) as Graphics.ColorValue {
        return colorSeverity(a) >= colorSeverity(b) ? a : b;
    }

    hidden function formatBatteryPct(status as AntPlus.BatteryStatusValue) as String {
        var pct = batteryStatusToPercent(status);
        if (pct >= 0.0f) {
            return pct.format("%d") + "%";
        }
        return "--";
    }

    hidden function deviceBatteryColor(pct as Float) as Graphics.ColorValue {
        return percentToColor(pct);
    }

    hidden function batteryStatusToPercent(status as AntPlus.BatteryStatusValue) as Float {
        switch (status) {
            case AntPlus.BATT_STATUS_NEW: return 100.0f;
            case AntPlus.BATT_STATUS_GOOD: return 75.0f;
            case AntPlus.BATT_STATUS_OK: return 50.0f;
            case AntPlus.BATT_STATUS_LOW: return 25.0f;
            case AntPlus.BATT_STATUS_CRITICAL: return 10.0f;
            default: return -1.0f;
        }
    }


}

class MyShiftingListener extends AntPlus.ShiftingListener {
    private const COMMON_BATTERY_PAGE = 0x52;
    private const MAX_BATTERIES = 4;

    private var mFrontGear as Number or Null;
    private var mRearGear as Number or Null;
    private var mBatteryStatus as AntPlus.BatteryStatusValue;
    private var mBatteryVoltage as Float or Null;
    private var mIsConnected as Boolean;
    private var mDeviceState as Number;
    private var mDeviceNumber as Number;
    private var mSerialNumber as Number;
    private var mShiftCallCount as Number;
    private var mBattCallCount as Number;
    private var mStateCallCount as Number;
    private var mRawMsgCount as Number;
    private var mBatteryFromRaw as Boolean;

    private var mRawBattVoltages as Array<Float>;
    private var mRawBattStatuses as Array<Number>;
    private var mRawBattCount as Number;
    private var mRawBattTotal as Number;

    function initialize() {
        ShiftingListener.initialize();
        mFrontGear = null;
        mRearGear = null;
        mBatteryStatus = AntPlus.BATT_STATUS_INVALID;
        mBatteryVoltage = null;
        mIsConnected = false;
        mDeviceState = -1;
        mDeviceNumber = 0;
        mSerialNumber = 0;
        mShiftCallCount = 0;
        mBattCallCount = 0;
        mStateCallCount = 0;
        mRawMsgCount = 0;
        mBatteryFromRaw = false;

        mRawBattVoltages = new Array<Float>[MAX_BATTERIES];
        mRawBattStatuses = new Array<Number>[MAX_BATTERIES];
        mRawBattCount = 0;
        mRawBattTotal = 0;
        for (var i = 0; i < MAX_BATTERIES; i++) {
            mRawBattVoltages[i] = -1.0f;
            mRawBattStatuses[i] = -1;
        }
    }

    function onShiftingUpdate(data as AntPlus.ShiftingStatus) as Void {
        mIsConnected = true;
        mShiftCallCount++;
        if (data != null) {
            if (data.frontDerailleur != null && data.frontDerailleur has :currentGear) {
                mFrontGear = data.frontDerailleur.currentGear;
            }
            if (data.rearDerailleur != null && data.rearDerailleur has :currentGear) {
                mRearGear = data.rearDerailleur.currentGear;
            }
            WatchUi.requestUpdate();
        }
    }

    function onBatteryStatusUpdate(data as AntPlus.BatteryStatus) as Void {
        mBattCallCount++;
        if (data != null && data.batteryStatus != null) {
            mBatteryStatus = data.batteryStatus;
            mBatteryFromRaw = false;
            if (data.batteryVoltage != null) {
                mBatteryVoltage = data.batteryVoltage as Float;
            }
            WatchUi.requestUpdate();
        }
    }

    function onMessage(msg as Ant.Message) as Void {
        var payload = msg.getPayload();
        if (Ant.MSG_ID_BROADCAST_DATA == msg.messageId) {
            mRawMsgCount++;
            var pageNum = (payload[0] & 0x7F);
            // Common page 81 — 32-bit serial (often usable as match ID)
            if (pageNum == 0x51 && payload.size() >= 8) {
                var sn = (payload[4] & 0xFF)
                    | ((payload[5] & 0xFF) << 8)
                    | ((payload[6] & 0xFF) << 16)
                    | ((payload[7] & 0xFF) << 24);
                if (sn > 0) {
                    mSerialNumber = sn;
                }
            }
            if (pageNum == COMMON_BATTERY_PAGE) {
                var battId = ((payload[2] >> 4) & 0x0F);
                var numBatt = (payload[2] & 0x0F);
                var fracVolt = (payload[6] & 0xFF);
                var coarseVolt = (payload[7] & 0x0F);
                var v = coarseVolt.toFloat() + (fracVolt.toFloat() / 256.0f);
                var statusBits = ((payload[7] >> 4) & 0x07);

                if (v > 0.5f) {
                    mBatteryVoltage = v;
                    mBatteryFromRaw = true;
                }
                switch (statusBits) {
                    case 1: mBatteryStatus = AntPlus.BATT_STATUS_NEW; break;
                    case 2: mBatteryStatus = AntPlus.BATT_STATUS_GOOD; break;
                    case 3: mBatteryStatus = AntPlus.BATT_STATUS_OK; break;
                    case 4: mBatteryStatus = AntPlus.BATT_STATUS_LOW; break;
                    case 5: mBatteryStatus = AntPlus.BATT_STATUS_CRITICAL; break;
                }

                if (battId < MAX_BATTERIES) {
                    if (v > 0.5f) { mRawBattVoltages[battId] = v; }
                    mRawBattStatuses[battId] = statusBits;
                    if (battId >= mRawBattCount) { mRawBattCount = battId + 1; }
                    mRawBattTotal = (numBatt > 0) ? numBatt : mRawBattCount;
                }
            }
        }
    }

    function onDeviceStateUpdate(data as AntPlus.DeviceState) as Void {
        mStateCallCount++;
        if (data != null && data.state != null) {
            mDeviceState = data.state as Number;
            // DeviceState.deviceNumber is a field — do not use `has` (dict-only)
            if (data.deviceNumber != null && (data.deviceNumber as Number) > 0) {
                mDeviceNumber = data.deviceNumber as Number;
            }
            if (data.state == AntPlus.DEVICE_STATE_DEAD || data.state == AntPlus.DEVICE_STATE_CLOSED) {
                mIsConnected = false;
                mBatteryStatus = AntPlus.BATT_STATUS_INVALID;
                mBatteryVoltage = null;
                mFrontGear = null;
                mRearGear = null;
            } else if (data.state == AntPlus.DEVICE_STATE_SEARCHING || data.state == AntPlus.DEVICE_STATE_TRACKING) {
                mIsConnected = (data.state == AntPlus.DEVICE_STATE_TRACKING);
            }
            WatchUi.requestUpdate();
        }
    }

    public function isConnected() as Boolean {
        return mIsConnected;
    }

    public function getDeviceState() as Number {
        return mDeviceState;
    }

    public function getDeviceNumber() as Number {
        return mDeviceNumber;
    }

    public function getSerialNumber() as Number {
        return mSerialNumber;
    }

    public function getCallCounts() as String {
        return "s" + mShiftCallCount + "/b" + mBattCallCount + "/d" + mStateCallCount;
    }

    public function getBatteryStatus() as AntPlus.BatteryStatusValue {
        return mBatteryStatus;
    }

    public function getBatteryVoltage() as Float or Null {
        return mBatteryVoltage;
    }

    public function getRawMsgCount() as Number { return mRawMsgCount; }
    public function isBatteryFromRaw() as Boolean { return mBatteryFromRaw; }
    public function getRawBatteryCount() as Number { return mRawBattCount; }
    public function getRawBatteryTotal() as Number { return mRawBattTotal; }
    public function getRawBatteryVoltage(idx as Number) as Float { return (idx < MAX_BATTERIES) ? mRawBattVoltages[idx] : -1.0f; }
    public function getRawBatteryStatus(idx as Number) as Number { return (idx < MAX_BATTERIES) ? mRawBattStatuses[idx] : -1; }

    public function getGearText() as String {
        if (mFrontGear != null && mRearGear != null) {
            return mFrontGear.format("%d") + "x" + mRearGear.format("%d");
        }
        if (mRearGear != null) {
            return mRearGear.format("%d");
        }
        return "--";
    }
}

class MyBikeRadarListener extends AntPlus.BikeRadarListener {
    private var mThreatCount as Number;
    private var mIsConnected as Boolean;

    function initialize() {
        BikeRadarListener.initialize();
        mThreatCount = 0;
        mIsConnected = false;
    }

    function onTrackingUpdate(data as AntPlus.BikeRadarUpdate) as Void {
        mIsConnected = true;
        if (data != null && data has :threats && data.threats != null) {
            mThreatCount = data.threats.size();
            WatchUi.requestUpdate();
        }
    }

    function onDeviceStateUpdate(data as AntPlus.DeviceState) as Void {
        if (data != null && data.state != null) {
            if (data.state == AntPlus.DEVICE_STATE_DEAD || data.state == AntPlus.DEVICE_STATE_CLOSED) {
                mIsConnected = false;
                mThreatCount = 0;
            } else if (data.state == AntPlus.DEVICE_STATE_TRACKING) {
                mIsConnected = true;
            }
            WatchUi.requestUpdate();
        }
    }

    public function isConnected() as Boolean {
        return mIsConnected;
    }

    public function hasThreat() as Boolean {
        return mIsConnected && mThreatCount > 0;
    }

    public function getStatus() as String {
        return mThreatCount.format("%d") + " Car" + (mThreatCount > 1 ? "s" : "");
    }
}

class MyLightNetworkListener extends AntPlus.LightNetworkListener {
    private var mRearMode as Number or Null;
    private var mFrontMode as Number or Null;
    private var mRearIndex as Number or Null;
    private var mFrontIndex as Number or Null;
    private var mHasRear as Boolean;
    private var mHasFront as Boolean;
    private var mNetworkFormed as Boolean;

    function initialize() {
        LightNetworkListener.initialize();
        mRearMode = null;
        mFrontMode = null;
        mRearIndex = null;
        mFrontIndex = null;
        mHasRear = false;
        mHasFront = false;
        mNetworkFormed = false;
    }

    function onBikeLightUpdate(data as AntPlus.BikeLight) as Void {
        var isHead = (data has :type && data.type == AntPlus.LIGHT_TYPE_HEADLIGHT);
        var mode = (data has :mode) ? data.mode : null;
        var lightIdx = (data has :identifier) ? data.identifier : null;
        if (isHead) {
            mHasFront = true;
            mFrontMode = mode;
            mFrontIndex = lightIdx;
        } else {
            mHasRear = true;
            mRearMode = mode;
            mRearIndex = lightIdx;
        }
        WatchUi.requestUpdate();
    }

    function onLightNetworkStateUpdate(data as AntPlus.LightNetworkState) as Void {
        if (data == AntPlus.LIGHT_NETWORK_STATE_FORMED) {
            mNetworkFormed = true;
        } else {
            mNetworkFormed = false;
            mRearMode = null;
            mFrontMode = null;
            mRearIndex = null;
            mFrontIndex = null;
            mHasRear = false;
            mHasFront = false;
        }
        WatchUi.requestUpdate();
    }

    public function isNetworkFormed() as Boolean {
        return mNetworkFormed;
    }

    public function hasRearLight() as Boolean {
        return mNetworkFormed && mHasRear;
    }

    public function hasFrontLight() as Boolean {
        return mNetworkFormed && mHasFront;
    }

    public function getRearIndex() as Number or Null {
        return mRearIndex;
    }

    public function getFrontIndex() as Number or Null {
        return mFrontIndex;
    }

    hidden function modeToString(m as Number or Null) as String {
        if (m == null) { return "--"; }
        switch (m) {
            case AntPlus.LIGHT_MODE_OFF: return "Off";
            case AntPlus.LIGHT_MODE_ST_81_100: return "High";
            case AntPlus.LIGHT_MODE_ST_61_80: return "Med-Hi";
            case AntPlus.LIGHT_MODE_ST_41_60: return "Medium";
            case AntPlus.LIGHT_MODE_ST_21_40: return "Med-Lo";
            case AntPlus.LIGHT_MODE_ST_0_20: return "Low";
            case AntPlus.LIGHT_MODE_SLOW_FLASH: return "SlowFlash";
            case AntPlus.LIGHT_MODE_FAST_FLASH: return "FastFlash";
            case AntPlus.LIGHT_MODE_RANDOM_FLASH: return "RndFlash";
            case AntPlus.LIGHT_MODE_AUTO: return "Auto";
            case AntPlus.LIGHT_MODE_SIGNAL_LEFT_SC: return "SigL-SC";
            case AntPlus.LIGHT_MODE_SIGNAL_LEFT: return "SigLeft";
            case AntPlus.LIGHT_MODE_SIGNAL_RIGHT_SC: return "SigR-SC";
            case AntPlus.LIGHT_MODE_SIGNAL_RIGHT: return "SigRight";
            case AntPlus.LIGHT_MODE_HAZARD: return "Hazard";
            default: return "M" + m.format("%d");
        }
    }

    public function getRearLightMode() as String {
        return modeToString(mRearMode);
    }

    public function getFrontLightMode() as String {
        return modeToString(mFrontMode);
    }
}

class MyBikePowerListener extends AntPlus.BikePowerListener {
    private var mIsConnected as Boolean;
    private var mDeviceNumber as Number;

    function initialize() {
        BikePowerListener.initialize();
        mIsConnected = false;
        mDeviceNumber = 0;
    }

    function onBikePowerUpdate(data as AntPlus.BikePowerData) as Void {
        mIsConnected = true;
    }

    function onBatteryStatusUpdate(data as AntPlus.BatteryStatus) as Void {
        mIsConnected = true;
    }

    function onDeviceStateUpdate(data as AntPlus.DeviceState) as Void {
        if (data != null && data.state != null) {
            if (data.deviceNumber != null && (data.deviceNumber as Number) > 0) {
                mDeviceNumber = data.deviceNumber as Number;
            }
            if (data.state == AntPlus.DEVICE_STATE_DEAD || data.state == AntPlus.DEVICE_STATE_CLOSED) {
                mIsConnected = false;
            } else if (data.state == AntPlus.DEVICE_STATE_TRACKING) {
                mIsConnected = true;
            }
        }
    }

    public function isConnected() as Boolean {
        return mIsConnected;
    }

    public function getDeviceNumber() as Number {
        return mDeviceNumber;
    }
}

class MyBikeCadenceListener extends AntPlus.BikeCadenceListener {
    private var mIsConnected as Boolean;

    function initialize() {
        BikeCadenceListener.initialize();
        mIsConnected = false;
    }

    function onBikeCadenceUpdate(data as AntPlus.BikeCadenceInfo) as Void {
        mIsConnected = true;
    }

    function onDeviceStateUpdate(data as AntPlus.DeviceState) as Void {
        if (data != null && data.state != null) {
            if (data.state == AntPlus.DEVICE_STATE_DEAD || data.state == AntPlus.DEVICE_STATE_CLOSED) {
                mIsConnected = false;
            } else if (data.state == AntPlus.DEVICE_STATE_TRACKING) {
                mIsConnected = true;
            }
        }
    }

    public function isConnected() as Boolean { return mIsConnected; }
}

class MyBikeSpeedListener extends AntPlus.BikeSpeedListener {
    private var mIsConnected as Boolean;

    function initialize() {
        BikeSpeedListener.initialize();
        mIsConnected = false;
    }

    function onBikeSpeedUpdate(data as AntPlus.BikeSpeedInfo) as Void {
        mIsConnected = true;
    }

    function onDeviceStateUpdate(data as AntPlus.DeviceState) as Void {
        if (data != null && data.state != null) {
            if (data.state == AntPlus.DEVICE_STATE_DEAD || data.state == AntPlus.DEVICE_STATE_CLOSED) {
                mIsConnected = false;
            } else if (data.state == AntPlus.DEVICE_STATE_TRACKING) {
                mIsConnected = true;
            }
        }
    }

    public function isConnected() as Boolean { return mIsConnected; }
}
