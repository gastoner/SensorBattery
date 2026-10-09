import Toybox.Activity;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.Test;

(:test)
class RegisteredSensorFixture {
    var name as String;
    var type as Sensor.SensorType;
    var enabled as Boolean = true;
    var data as Dictionary;
    function initialize(sensorType as Sensor.SensorType, label as String, id as Number) {
        type = sensorType;
        name = label;
        data = { :antSerialNumber => id };
    }
}

(:test)
class IdentityFeedViewProbe extends SensorBatteryView {
    function initialize(slot as Number) {
        SensorBatteryView.initialize();
        mBleMgr = new BleManagerProbe(false, slot == 1, slot == 2);
    }

    // Avoid opening native ANT channels or changing persistent settings in tests.
    public function loadSettings() as Void {}

    (:typecheck(false))
    protected function registeredSensors(sensorType as Sensor.SensorType) as Sensor.SensorInfoIterator {
        if (sensorType == Sensor.SENSOR_HEARTRATE) {
            return new BleScanIterator([
                new RegisteredSensorFixture(sensorType, "My strap", 12345)
            ]);
        }
        return new BleScanIterator([
            new RegisteredSensorFixture(sensorType, "My power meter", 23456)
        ]);
    }

    function manager() as BleManagerProbe { return mBleMgr as BleManagerProbe; }
}

// Exercise the complete compute -> registry -> candidate feed. Calling the
// manager alone misses the large caller frame responsible for the Edge 530 crash.
(:test)
function viewFeedsHrmAndPmIdsDuringCompute(logger as Test.Logger) as Boolean {
    for (var slot = 1; slot <= 2; slot++) {
        var view = new IdentityFeedViewProbe(slot);
        view.compute(Activity.getActivityInfo());
        var mgr = view.manager();
        Test.assert(mgr.getAntMatchDebug(1).find("12345") != null);
        Test.assert(mgr.getAntMatchDebug(2).find("23456") != null);
        var matchingName = slot == 1 ? "HRM 12345" : "PM 23456";
        mgr.scan(slot, [new BleScanFixture(slot, "Nearby sensor", -20),
            new BleScanFixture(slot, matchingName, -80)]);
        mgr.pair();
        Test.assertEqual(mgr.lastName, matchingName);
        mgr.stop();
    }
    return true;
}
