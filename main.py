import sys
import os
import shutil
import subprocess
from PyQt6 import QtWidgets
from mainwindow import Ui_MainWindow
from general import load_general_config, apply_general_config
from automaticTestMode import load_automatic_test_mode_config, apply_automatic_test_mode_config
from prime95 import load_prime95_config, apply_prime95_config
from prime95Custom import load_prime95_custom_config, apply_prime95_custom_config
from aida64 import load_aida64_config, apply_aida64_config
from ycruncher import load_ycruncher_config, apply_ycruncher_config
from update import load_update_config, apply_update_config
from logging import load_logging_config, apply_logging_config
from debugging import load_debug_config, apply_debug_config
from linpack import load_linpack_config, apply_linpack_config
from reset import reset_config
from tools import (
    launch_boost_tester,
    launch_pbo2_tuner,
    launch_intel_voltage_control,
    launch_apic_ids,
    launch_core_tuner_x,
    launch_enable_performance_counters,
    open_helpers_folder
)
import start

# Load all settings at startup
def load_all_configs(ui):
    load_general_config(ui)
    load_automatic_test_mode_config(ui)
    load_prime95_config(ui)
    load_prime95_custom_config(ui)
    load_aida64_config(ui)
    load_ycruncher_config(ui)
    load_update_config(ui)
    load_logging_config(ui)
    load_debug_config(ui)
    load_linpack_config(ui)

# Apply all settings when Apply is clicked
def apply_all_configs(ui):
    apply_general_config(ui)
    apply_automatic_test_mode_config(ui)
    apply_prime95_config(ui)
    apply_prime95_custom_config(ui)
    apply_aida64_config(ui)
    apply_ycruncher_config(ui)
    apply_update_config(ui)
    apply_logging_config(ui)
    apply_debug_config(ui)
    apply_linpack_config(ui)

if __name__ == "__main__":
    app = QtWidgets.QApplication(sys.argv)
    MainWindow = QtWidgets.QMainWindow()
    ui = Ui_MainWindow()
    ui.setupUi(MainWindow)
    
    load_all_configs(ui)
    ui.apply_config_pushButton.clicked.connect(lambda: apply_all_configs(ui))
    ui.reset_config_pushButton.clicked.connect(reset_config)

    ui.boostTester_pushButton.clicked.connect(launch_boost_tester)
    ui.pbo2Tuner_pushButton.clicked.connect(launch_pbo2_tuner)
    ui.intelVoltageControl_pushButton.clicked.connect(launch_intel_voltage_control)
    ui.apicIds_pushButton.clicked.connect(launch_apic_ids)
    ui.coreTunerX_pushButton.clicked.connect(launch_core_tuner_x)
    ui.enablePerformanceCounters_pushButton.clicked.connect(launch_enable_performance_counters)
    ui.helpers_pushButton.clicked.connect(open_helpers_folder)

    ui.start_test_pushButton.clicked.connect(lambda: start.run_corecycler(MainWindow))
    
    MainWindow.show()
    sys.exit(app.exec())
