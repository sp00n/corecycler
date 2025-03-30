import os
import shutil
import subprocess
import sys
from PyQt6 import QtWidgets

def reset_config():
    """
    Resets the configuration by copying default.config.ini to config.ini and restarts the application.
    """
    # Ask for user confirmation before resetting
    reply = QtWidgets.QMessageBox.question(
        None,
        "Confirm Reset",
        "Are you sure you want to reset to default settings?",
        QtWidgets.QMessageBox.StandardButton.Yes | QtWidgets.QMessageBox.StandardButton.No,
        QtWidgets.QMessageBox.StandardButton.No  # Default button is 'No'
    )
    if reply == QtWidgets.QMessageBox.StandardButton.Yes:
        # Get the current working directory where config.ini resides
        working_dir = os.getcwd()
        default_config_path = os.path.join(working_dir, 'configs', 'default.config.ini')
        config_path = os.path.join(working_dir, 'config.ini')
        
        # Check if the default config file exists
        if not os.path.exists(default_config_path):
            QtWidgets.QMessageBox.warning(
                None,
                "Warning",
                f"Default config file not found at {default_config_path}."
            )
            return
        
        try:
            # Copy default.config.ini to config.ini, overwriting if it exists
            shutil.copyfile(default_config_path, config_path)
        except Exception as e:
            QtWidgets.QMessageBox.critical(
                None,
                "Error",
                f"Failed to copy default config: {e}"
            )
            return
        
        try:
            # Restart the application
            subprocess.Popen([sys.executable, 'main.py'], cwd=working_dir)
        except Exception as e:
            QtWidgets.QMessageBox.critical(
                None,
                "Error",
                f"Failed to restart application: {e}"
            )
            return
        
        # Quit the current application instance
        QtWidgets.QApplication.quit()
