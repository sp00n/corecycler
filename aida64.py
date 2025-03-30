import configparser

def load_aida64_config(ui):
    """
    Load settings from the [Aida64] section of config.ini into the GUI.
    
    Args:
        ui: The GUI object containing the widgets to be updated.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')
    
    if 'Aida64' in config:
        aida64 = config['Aida64']
        
        # Load mode: split the comma-separated string and check corresponding checkboxes
        mode = aida64.get('mode', '')
        modes = [m.strip() for m in mode.split(',') if m.strip()]
        ui.aida64_mode_cache_checkBox.setChecked('Cache' in modes)
        ui.aida64_mode_cpu_checkBox.setChecked('CPU' in modes)
        ui.aida64_mode_fpu_checkBox.setChecked('FPU' in modes)
        ui.aida64_mode_ram_checkBox.setChecked('RAM' in modes)
        
        # Load useAvx: set checkbox based on '0' or '1'
        use_avx = aida64.get('useAvx', '0')
        ui.aida64_useAvx_checkBox.setChecked(use_avx == '1')
        
        # Load maxMemory: set spinbox value, default to 80 if invalid
        max_memory = aida64.get('maxMemory', '80')
        try:
            ui.aida64_maxMemory_spinBox.setValue(int(max_memory))
        except ValueError:
            ui.aida64_maxMemory_spinBox.setValue(80)
    else:
        # If [Aida64] section is missing, set default GUI values
        ui.aida64_mode_cache_checkBox.setChecked(False)
        ui.aida64_mode_cpu_checkBox.setChecked(False)
        ui.aida64_mode_fpu_checkBox.setChecked(False)
        ui.aida64_mode_ram_checkBox.setChecked(False)
        ui.aida64_useAvx_checkBox.setChecked(False)
        ui.aida64_maxMemory_spinBox.setValue(80)

def apply_aida64_config(ui):
    """
    Apply current GUI settings to the [Aida64] section of config.ini.
    
    Args:
        ui: The GUI object containing the widgets with current values.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')
    
    # Ensure [Aida64] section exists
    if 'Aida64' not in config:
        config['Aida64'] = {}
    
    aida64 = config['Aida64']
    
    # Apply mode: collect checked modes and join with ', '
    modes = []
    if ui.aida64_mode_cache_checkBox.isChecked():
        modes.append('Cache')
    if ui.aida64_mode_cpu_checkBox.isChecked():
        modes.append('CPU')
    if ui.aida64_mode_fpu_checkBox.isChecked():
        modes.append('FPU')
    if ui.aida64_mode_ram_checkBox.isChecked():
        modes.append('RAM')
    aida64['mode'] = ', '.join(modes)
    
    # Apply useAvx: '1' if checked, '0' otherwise
    aida64['useAvx'] = '1' if ui.aida64_useAvx_checkBox.isChecked() else '0'
    
    # Apply maxMemory: convert spinbox value to string
    aida64['maxMemory'] = str(ui.aida64_maxMemory_spinBox.value())
    
    # Write the updated config to file
    with open('config.ini', 'w') as configfile:
        config.write(configfile)
