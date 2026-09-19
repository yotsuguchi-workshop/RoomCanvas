#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR=$(mktemp -d)
trap 'rm -rf "$CHECK_DIR"' EXIT
python3 - "$CHECK_DIR" <<'PYTHON'
from pathlib import Path
import sys
out=Path(sys.argv[1])
s=Path('RoomCanvas/DisplayServices.swift').read_text()
out.joinpath('Services.swift').write_text(s.split('@MainActor final class WeatherStore')[0])
ble=Path('RoomCanvas/BLELab.swift').read_text()
out.joinpath('Remote.swift').write_text('import Foundation\n'+ble[ble.index('struct RemotePressDetector'):ble.index('@MainActor final class BLELab')])
s=Path('RoomCanvas/Dashboard.swift').read_text()
a=s.index('extension Color {'); b=s.index('\n}',a)+2
out.joinpath('Colors.swift').write_text('import SwiftUI\n'+s[a:b])
PYTHON
xcrun swiftc -parse-as-library RoomCanvas/Models.swift "$CHECK_DIR/Services.swift" RoomCanvas/BundledHolidays.swift RoomCanvas/SwitchBotDevices.swift "$CHECK_DIR/Colors.swift" "$CHECK_DIR/Remote.swift" scripts/PolicyChecks.swift -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
