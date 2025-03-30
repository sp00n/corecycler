import configparser

def load_debug_config(ui, config_file='config.ini'):
    """
    Load settings from the [Debug] section of the config file into the GUI elements.
    
    Args:
        ui: The Ui_MainWindow instance containing the GUI elements.
        config_file (str): Path to the config file (default: 'config.ini').
    """
    config = configparser.ConfigParser()
    config.read(config_file)
    
    # Load checkbox settings (boolean, stored as 0 or 1)
    ui.debug_disableCpuUtilizationCheck_checkBox.setChecked(
        config.getboolean('Debug', 'disablecpuutilizationcheck', fallback=False))
    ui.debug_useWindowsPerformanceCountersForCpuUtilization_checkBox.setChecked(
        config.getboolean('Debug', 'usewindowsperformancecountersforcpuutilization', fallback=False))
    ui.debug_enableCpuFrequencyCheck_checkBox.setChecked(
        config.getboolean('Debug', 'enablecpufrequencycheck', fallback=False))
    ui.debug_delayFirstErrorCheck_checkBox.setChecked(
        config.getboolean('Debug', 'delayfirsterrorcheck', fallback=False))
    ui.debug_stressTestProgramWindowToForeground_checkBox.setChecked(
        config.getboolean('Debug', 'stresstestprogramwindowtoforeground', fallback=False))
    
    # Load combo box settings (strings)
    ui.debug_stressTestProgramPriority_comboBox.setCurrentText(
        config.get('Debug', 'stresstestprogrampriority', fallback='Normal'))
    ui.debug_modeToUseForSuspension_comboBox.setCurrentText(
        config.get('Debug', 'modetouseforsuspension', fallback='Threads'))
    
    # Load spin box settings (integers)
    ui.debug_suspensionTime_spinBox.setValue(
        config.getint('Debug', 'suspensiontime', fallback=1000))
    ui.debug_tickInterval_spinBox.setValue(
        config.getint('Debug', 'tickinterval', fallback=10))

def apply_debug_config(ui, config_file='config.ini'):
    """
    Apply settings from the GUI elements to the [Debug] section of the config file.
    
    Args:
        ui: The Ui_MainWindow instance containing the GUI elements.
        config_file (str): Path to the config file (default: 'config.ini').
    """
    config = configparser.ConfigParser()
    config.read(config_file)
    
    # Ensure the [Debug] section exists
    if not config.has_section('Debug'):
        config.add_section('Debug')
    
    # Apply checkbox settings (convert boolean to '0' or '1')
    config.set('Debug', 'disablecpuutilizationcheck',
               '1' if ui.debug_disableCpuUtilizationCheck_checkBox.isChecked() else '0')
    config.set('Debug', 'usewindowsperformancecountersforcpuutilization',
               '1' if ui.debug_useWindowsPerformanceCountersForCpuUtilization_checkBox.isChecked() else '0')
    config.set('Debug', 'enablecpufrequencycheck',
               '1' if ui.debug_enableCpuFrequencyCheck_checkBox.isChecked() else '0')
    config.set('Debug', 'delayfirsterrorcheck',
               '1' if ui.debug_delayFirstErrorCheck_checkBox.isChecked() else '0')
    config.set('Debug', 'stresstestprogramwindowtoforeground',
               '1' if ui.debug_stressTestProgramWindowToForeground_checkBox.isChecked() else '0')
    
    # Apply combo box settings (get selected text)
    config.set('Debug', 'stresstestprogrampriority',
               ui.debug_stressTestProgramPriority_comboBox.currentText())
    config.set('Debug', 'modetouseforsuspension',
               ui.debug_modeToUseForSuspension_comboBox.currentText())
    
    # Apply spin box settings (convert integer to string)
    config.set('Debug', 'suspensiontime',
               str(ui.debug_suspensionTime_spinBox.value()))
    config.set('Debug', 'tickinterval',
               str(ui.debug_tickInterval_spinBox.value()))
    
    # Write the updated config back to the file
    with open(config_file, 'w') as configfile:
        config.write(configfile)
