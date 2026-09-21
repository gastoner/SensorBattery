import Toybox.Lang;

module FontZoom {

    function rowBaseline(rowHeight as Number, screenWidth as Number) as Number {
        if (screenWidth >= 400) {
            if (rowHeight >= 42) { return 3; }
            if (rowHeight >= 28) { return 2; }
            return 1;
        }

        if (screenWidth >= 280) {
            if (rowHeight >= 90) { return 4; }
            if (rowHeight >= 55) { return 3; }
            if (rowHeight >= 38) { return 2; }
            return 1;
        }

        if (rowHeight >= 55) { return 3; }
        if (rowHeight >= 38) { return 2; }
        if (rowHeight >= 26) { return 1; }
        return 0;
    }

    function rowIndex(baseIdx as Number, zoom as Number, maxIdx as Number) as Number {
        if (baseIdx < 2) { baseIdx = 2; }
        if (baseIdx > maxIdx) { baseIdx = maxIdx; }

        var idx = baseIdx - zoom;
        if (zoom >= 2 && baseIdx == 4) { idx = 1; }
        if (idx < 0) { return 0; }
        if (idx > maxIdx) { return maxIdx; }
        return idx;
    }

}
