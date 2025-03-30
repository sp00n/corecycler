import configparser

def load_linpack_config(ui):
    """
    Load settings from the [Linpack] section of config.ini and update the GUI combo boxes.
    
    Args:
        ui: The UI object from mainwindow.py containing the GUI elements.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')
    
    if 'Linpack' in config:
        linpack = config['Linpack']
        
        # Load version setting into linpack_version_comboBox
        version = linpack.get('version', '2021')  # Default to '2021' if not found
        ui.linpack_version_comboBox.setCurrentText(version)
        
        # Load mode setting into linpack_mode_comboBox
        mode = linpack.get('mode', 'Fast')  # Default to 'Fast' if not found
        ui.linpack_mode_comboBox.setCurrentText(mode)
        
        # Load memory setting into linpack_memory_comboBox
        memory = linpack.get('memory', '6GB')  # Default to '6GB' if not found
        ui.linpack_memory_comboBox.setCurrentText(memory)
    else:
        # If [Linpack] section doesn't exist, set combo boxes to their first item
        ui.linpack_version_comboBox.setCurrentIndex(0)
        ui.linpack_mode_comboBox.setCurrentIndex(0)
        ui.linpack_memory_comboBox.setCurrentIndex(0)

def apply_linpack_config(ui):
    """
    Update the [Linpack] section in config.ini based on current GUI combo box selections.
    
    Args:
        ui: The UI object from mainwindow.py containing the GUI elements.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')
    
    # Create [Linpack] section if it doesn't exist
    if 'Linpack' not in config:
        config['Linpack'] = {}
    
    linpack = config['Linpack']
    
    # Update version setting from linpack_version_comboBox
    version = ui.linpack_version_comboBox.currentText()
    linpack['version'] = version
    
    # Update mode setting from linpack_mode_comboBox
    mode = ui.linpack_mode_comboBox.currentText()
    linpack['mode'] = mode
    
    # Update memory setting from linpack_memory_comboBox
    memory = ui.linpack_memory_comboBox.currentText()
    linpack['memory'] = memory
    
    # Write the updated configuration back to config.ini
    with open('config.ini', 'w') as configfile:
        config.write(configfile)
