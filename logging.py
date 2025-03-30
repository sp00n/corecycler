import configparser

def load_logging_config(ui):
    """
    Load settings from the [Logging] section of config.ini into the GUI.
    
    Args:
        ui: The GUI object containing the widgets to be updated.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')
    
    if 'Logging' in config:
        logging = config['Logging']
        
        # Load name (default to "corecycler")
        name = logging.get('name', 'corecycler')
        ui.logging_name_lineEdit.setText(name)
        
        # Load logLevel (default to 0)
        log_level = logging.get('loglevel', '0')
        try:
            ui.logging_logLevel_spinBox.setValue(int(log_level))
        except ValueError:
            ui.logging_logLevel_spinBox.setValue(0)
        
        # Load useWindowsEventLog (default to '0')
        use_windows_event_log = logging.get('usewindowseventlog', '0')
        ui.logging_useWindowsEventLog_checkBox.setChecked(use_windows_event_log == '1')
        
        # Load flushDiskWriteCache (default to '0')
        flush_disk_write_cache = logging.get('flushdiskwritecache', '0')
        ui.logging_flushDiskWriteCache_checkBox.setChecked(flush_disk_write_cache == '1')
    else:
        # Set defaults if [Logging] section is missing
        ui.logging_name_lineEdit.setText('corecycler')
        ui.logging_logLevel_spinBox.setValue(0)
        ui.logging_useWindowsEventLog_checkBox.setChecked(False)
        ui.logging_flushDiskWriteCache_checkBox.setChecked(False)

def apply_logging_config(ui):
    """
    Apply current GUI settings to the [Logging] section of config.ini.
    
    Args:
        ui: The GUI object containing the widgets with current values.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')
    
    # Ensure [Logging] section exists
    if 'Logging' not in config:
        config['Logging'] = {}
    
    logging = config['Logging']
    
    # Apply name
    logging['name'] = ui.logging_name_lineEdit.text() or 'corecycler'
    
    # Apply logLevel
    logging['loglevel'] = str(ui.logging_logLevel_spinBox.value())
    
    # Apply useWindowsEventLog
    logging['usewindowseventlog'] = '1' if ui.logging_useWindowsEventLog_checkBox.isChecked() else '0'
    
    # Apply flushDiskWriteCache
    logging['flushdiskwritecache'] = '1' if ui.logging_flushDiskWriteCache_checkBox.isChecked() else '0'
    
    # Write the updated config to file
    with open('config.ini', 'w') as configfile:
        config.write(configfile)
