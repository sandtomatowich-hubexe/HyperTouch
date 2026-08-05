#!/system/bin/sh
# Restores the stock PowerKeeper service when the module is removed,
# so uninstalling actually puts the phone back to stock behavior.
pm enable com.miui.powerkeeper/.statemachine.PowerStateMachineService >/dev/null 2>&1
