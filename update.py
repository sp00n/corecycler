import configparser

def load_update_config(ui):
    """
    Load settings from the [Update] section of config.ini into the GUI.

    Args:
        ui: The GUI object containing the widgets to be updated.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')
    if 'Update' in config:
        # Load enableUpdateCheck (default to '0' if not present)
        enable_update_check = config['Update'].get('enableUpdateCheck', '0')
        ui.update_enableUpdateCheck_checkBox.setChecked(enable_update_check == '1')
        
        # Load updateCheckFrequency (default to '7' if not present or invalid)
        update_check_frequency = config['Update'].get('updateCheckFrequency', '7')
        try:
            ui.update_updateCheckFrequency_spinBox.setValue(int(update_check_frequency))
        except ValueError:
            ui.update_updateCheckFrequency_spinBox.setValue(7)
    else:
        # If [Update] section is missing, set default values
        ui.update_enableUpdateCheck_checkBox.setChecked(False)
        ui.update_updateCheckFrequency_spinBox.setValue(7)

def apply_update_config(ui):
    """
    Apply current GUI settings to the [Update] section of config.ini.

    Args:
        ui: The GUI object containing the widgets with current values.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')
    if 'Update' not in config:
        config['Update'] = {}
    # Set enableUpdateCheck based on checkbox state
    config['Update']['enableUpdateCheck'] = '1' if ui.update_enableUpdateCheck_checkBox.isChecked() else '0'
    # Set updateCheckFrequency to the spinbox value as a string
    config['Update']['updateCheckFrequency'] = str(ui.update_updateCheckFrequency_spinBox.value())
    # Write the updated config to file
    with open('config.ini', 'w') as configfile:
        config.write(configfile)
