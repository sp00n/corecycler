import configparser

def load_prime95_config(ui):
    """
    Load settings from the [Prime95] section of config.ini and update the GUI elements.
    
    Args:
        ui: The UI object from mainwindow.py containing the GUI elements.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')
    
    if 'Prime95' in config:
        prime95 = config['Prime95']
        
        # Load mode
        mode = prime95.get('mode', 'SSE')  # Default to 'SSE' if not present
        ui.prime95_mode_comboBox.setCurrentText(mode)
        
        # Load fftSize
        fftsize = prime95.get('fftsize', 'All')  # Default to 'All' if not present
        predefined_options = ["Smallest", "Small", "Large", "Huge", "HeavyShort", 
                             "Moderate", "Heavy", "All"]
        if fftsize in predefined_options:
            ui.prime95_fftSize_comboBox.setCurrentText(fftsize)
            ui.prime95_fftSize_lineEdit.clear()
        else:
            ui.prime95_fftSize_comboBox.setCurrentText("Custom")
            ui.prime95_fftSize_lineEdit.setText(fftsize)
    else:
        # Set defaults if the [Prime95] section doesn't exist
        ui.prime95_mode_comboBox.setCurrentText("SSE")
        ui.prime95_fftSize_comboBox.setCurrentText("All")
        ui.prime95_fftSize_lineEdit.clear()

def apply_prime95_config(ui):
    """
    Update the [Prime95] section in config.ini based on current GUI settings.
    
    Args:
        ui: The UI object from mainwindow.py containing the GUI elements.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')
    
    # Ensure the [Prime95] section exists
    if 'Prime95' not in config:
        config['Prime95'] = {}
    
    prime95 = config['Prime95']
    
    # Set mode
    mode = ui.prime95_mode_comboBox.currentText()
    prime95['mode'] = mode
    
    # Set fftSize based on combo box selection
    fftsize_selection = ui.prime95_fftSize_comboBox.currentText()
    if fftsize_selection == "Custom":
        prime95['fftsize'] = ui.prime95_fftSize_lineEdit.text()
    else:
        prime95['fftsize'] = fftsize_selection
    
    # Write the updated configuration back to config.ini
    with open('config.ini', 'w') as configfile:
        config.write(configfile)
