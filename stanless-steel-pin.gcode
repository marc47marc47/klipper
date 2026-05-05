; Stainless steel pin pick-and-place test
; Target: Klippy <-> xyz-gripper Linux-MCU simulator (TCP 7878)
; Send via:  ./test-gcode.sh ./stanless-steel-pin.gcode
;
; The simulator has no real endstops, so we cannot run G28. Instead we
; declare the kinematic position with SET_KINEMATIC_POSITION and move
; inside a safe envelope (cfg limits: X -3..246, Y -10..255, Z -3..265).

; ---------- Diagnostics ----------
M115                                 ; firmware identifier
SET_KINEMATIC_POSITION X=0 Y=0 Z=20  ; pretend the toolhead is homed
GET_POSITION                         ; verify the synthetic home took
G90                                  ; absolute coordinates
M83                                  ; relative extrusion (no extruder used)

; ---------- Pick #1 ----------
G1 X10 Y10 F3000                     ; travel to pin 1
G1 Z5  F300                          ; descend to pick
G4 P200                              ; settle 0.2s
G1 Z20 F600                          ; lift

; ---------- Place #1 ----------
G1 X10 Y50 F3000                     ; travel to drop 1
G1 Z5  F300                          ; descend to release
G4 P200
G1 Z20 F600

; ---------- Pick #2 ----------
G1 X50 Y10 F3000                     ; travel to pin 2
G1 Z5  F300
G4 P200
G1 Z20 F600

; ---------- Place #2 ----------
G1 X50 Y50 F3000                     ; travel to drop 2
G1 Z5  F300
G4 P200
G1 Z20 F600

; ---------- Return ----------
G1 X0 Y0  F3000
M400                                 ; wait for the move queue to drain
GET_POSITION                         ; confirm final position
M118 stainless-steel-pin test done
