import configparser

def load_automatic_test_mode_config(ui):
    """
    Load settings from the [AutomaticTestMode] section of config.ini and update the GUI elements.
    
    Args:
        ui: The UI object from mainwindow.py containing the GUI elements.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')
    
    # Check if the [AutomaticTestMode] section exists
    if 'AutomaticTestMode' in config:
        atm = config['AutomaticTestMode']
        
        # Enable Automatic Adjustment (Checkbox)
        enable_automatic = atm.get('enableautomaticadjustment', '0')
        ui.automaticTestMode_enableAutomaticAdjustment_checkBox.setChecked(enable_automatic == '1')
        
        # Start Values (Line Edit)
        start_values = atm.get('startvalues', 'Default')
        ui.automaticTestMode_startValues_lineEdit.setText(start_values)
        
        # Max Value (SpinBox)
        try:
            max_value = int(atm.get('maxvalue', '15'))
            ui.automaticTestMode_maxValue_spinBox.setValue(max_value)
        except ValueError:
            ui.automaticTestMode_maxValue_spinBox.setValue(15)  # Default value
        
        # Increment By (SpinBox)
        try:
            increment_by = int(atm.get('incrementby', '1'))
            ui.automaticTestMode_incrementBy_spinBox.setValue(increment_by)
        except ValueError:
            ui.automaticTestMode_incrementBy_spinBox.setValue(1)  # Default value
        
        # Repeat Core On Error (Checkbox)
        repeat_core = atm.get('repeatcoreonerror', '0')
        ui.automaticTestMode_repeatCoreOnError_checkBox.setChecked(repeat_core == '1')
        
        # Enable Resume After Unexpected Exit (Checkbox)
        enable_resume = atm.get('enableresumeafterunexpectedexit', '0')
        ui.automaticTestMode_enableResumeAfterUnexpectedExit_checkBox.setChecked(enable_resume == '1')
    else:
        # If the section is missing, set default values in the GUI
        ui.automaticTestMode_enableAutomaticAdjustment_checkBox.setChecked(False)
        ui.automaticTestMode_startValues_lineEdit.setText('Default')
        ui.automaticTestMode_maxValue_spinBox.setValue(15)
        ui.automaticTestMode_incrementBy_spinBox.setValue(1)
        ui.automaticTestMode_repeatCoreOnError_checkBox.setChecked(False)
        ui.automaticTestMode_enableResumeAfterUnexpectedExit_checkBox.setChecked(False)

def apply_automatic_test_mode_config(ui):
    """
    Update the [AutomaticTestMode] section in config.ini based on current GUI settings.
    
    Args:
        ui: The UI object from mainwindow.py containing the GUI elements.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')
    
    # Ensure the [AutomaticTestMode] section exists
    if 'AutomaticTestMode' not in config:
        config['AutomaticTestMode'] = {}
    atm = config['AutomaticTestMode']
    
    # Enable Automatic Adjustment (Checkbox)
    atm['enableautomaticadjustment'] = '1' if ui.automaticTestMode_enableAutomaticAdjustment_checkBox.isChecked() else '0'
    
    # Start Values (Line Edit)
    atm['startvalues'] = ui.automaticTestMode_startValues_lineEdit.text()
    
    # Max Value (SpinBox)
    atm['maxvalue'] = str(ui.automaticTestMode_maxValue_spinBox.value())
    
    # Increment By (SpinBox)
    atm['incrementby'] = str(ui.automaticTestMode_incrementBy_spinBox.value())
    
    # Repeat Core On Error (Checkbox)
    atm['repeatcoreonerror'] = '1' if ui.automaticTestMode_repeatCoreOnError_checkBox.isChecked() else '0'
    
    # Enable Resume After Unexpected Exit (Checkbox)
    atm['enableresumeafterunexpectedexit'] = '1' if ui.automaticTestMode_enableResumeAfterUnexpectedExit_checkBox.isChecked() else '0'
    
    # Write the updated configuration back to config.ini
    with open('config.ini', 'w') as configfile:
        config.write(configfile)
