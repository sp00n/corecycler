import configparser

def load_prime95_custom_config(ui):
    """
    Load settings from the [Prime95Custom] section of config.ini into the GUI.
    
    Args:
        ui: The GUI object containing the widgets to be updated.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')
    
    # Check if the [Prime95Custom] section exists
    if 'Prime95Custom' in config:
        section = config['Prime95Custom']
        
        # Load checkbox states (0 or 1 from config)
        ui.pirme95Custom_cpuSupportsAvx_checkBox.setChecked(section.get('cpuSupportsAvx', '0') == '1')
        ui.prime95Custom_cpuSupportsAvx2_checkBox.setChecked(section.get('cpuSupportsAvx2', '0') == '1')
        ui.prime95Custom_cpuSupportsFma3_checkBox.setChecked(section.get('cpuSupportsFma3', '0') == '1')
        ui.prime95Custom_cpuSupportsAvx512_checkBox.setChecked(section.get('cpuSupportsAvx512', '0') == '1')
        
        # Load line edit texts with defaults
        ui.prime95Custom_minTortureFft_lineEdit.setText(section.get('minTortureFft', '4'))
        ui.prime95Custom_maxTortureFft_lineEdit.setText(section.get('maxTortureFft', '1344'))
        ui.prime95Custom_tortureMem_lineEdit.setText(section.get('tortureMem', '0'))
        
        # Load spinbox value, converting string to int with error handling
        try:
            torture_time = int(section.get('tortureTime', '1'))
        except ValueError:
            torture_time = 1  # Default to 1 if conversion fails
        ui.prime95Custom_tortureTime_spinBox.setValue(torture_time)
    else:
        # If section is missing, set default values in the GUI
        ui.pirme95Custom_cpuSupportsAvx_checkBox.setChecked(False)
        ui.prime95Custom_cpuSupportsAvx2_checkBox.setChecked(False)
        ui.prime95Custom_cpuSupportsFma3_checkBox.setChecked(False)
        ui.prime95Custom_cpuSupportsAvx512_checkBox.setChecked(False)
        ui.prime95Custom_minTortureFft_lineEdit.setText('4')
        ui.prime95Custom_maxTortureFft_lineEdit.setText('1344')
        ui.prime95Custom_tortureMem_lineEdit.setText('0')
        ui.prime95Custom_tortureTime_spinBox.setValue(1)

def apply_prime95_custom_config(ui):
    """
    Apply current GUI settings to the [Prime95Custom] section of config.ini.
    
    Args:
        ui: The GUI object containing the widgets with current values.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')
    
    # Ensure the [Prime95Custom] section exists
    if 'Prime95Custom' not in config:
        config['Prime95Custom'] = {}
    
    section = config['Prime95Custom']
    
    # Save checkbox states as '0' or '1'
    section['cpuSupportsAvx'] = '1' if ui.pirme95Custom_cpuSupportsAvx_checkBox.isChecked() else '0'
    section['cpuSupportsAvx2'] = '1' if ui.prime95Custom_cpuSupportsAvx2_checkBox.isChecked() else '0'
    section['cpuSupportsFma3'] = '1' if ui.prime95Custom_cpuSupportsFma3_checkBox.isChecked() else '0'
    section['cpuSupportsAvx512'] = '1' if ui.prime95Custom_cpuSupportsAvx512_checkBox.isChecked() else '0'
    
    # Save line edit texts directly
    section['minTortureFft'] = ui.prime95Custom_minTortureFft_lineEdit.text()
    section['maxTortureFft'] = ui.prime95Custom_maxTortureFft_lineEdit.text()
    section['tortureMem'] = ui.prime95Custom_tortureMem_lineEdit.text()
    
    # Save spinbox value as a string
    section['tortureTime'] = str(ui.prime95Custom_tortureTime_spinBox.value())
    
    # Write the updated config to file
    with open('config.ini', 'w') as configfile:
        config.write(configfile)
