import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class SensorBatteryApp extends Application.AppBase {

    private var mView as SensorBatteryView?;

    function initialize() {
        AppBase.initialize();
        mView = null;
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() {
        mView = new SensorBatteryView();
        return [ mView ];
    }

    function onSettingsChanged() as Void {
        if (mView != null) {
            mView.loadSettings();
        }
        WatchUi.requestUpdate();
    }

}

function getApp() as SensorBatteryApp {
    return Application.getApp() as SensorBatteryApp;
}