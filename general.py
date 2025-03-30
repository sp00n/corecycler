import configparser

def load_general_config(ui):
    """Load settings from config.ini and update the GUI elements for the [General] section."""
    config = configparser.ConfigParser()
    config.read('config.ini')
    
    # Check if the [General] section exists
    if 'General' in config:
        general = config['General']
        
        # Stress Test Program (Radio Buttons)
        stresstestprogram = general.get('stresstestprogram', '').upper()
        if stresstestprogram == 'PRIME95':
            ui.general_stressTestProgram_radioButton_prime95.setChecked(True)
        elif stresstestprogram == 'LINPACK':
            ui.general_stressTestProgram_radioButton_linpack.setChecked(True)
        elif stresstestprogram == 'AIDA64':
            ui.general_stressTestProgram_radioButton_aida64.setChecked(True)
        elif stresstestprogram == 'YCRUNCHER':
            ui.general_stressTestProgram_radioButton_ycruncher.setChecked(True)
        elif stresstestprogram == 'YCRUNCHER_OLD':
            ui.general_stressTestProgram_radioButton_ycruncher_old.setChecked(True)
        else:
            ui.general_stressTestProgram_radioButton_prime95.setChecked(True)  # Default
        
        # Checkboxes (Boolean settings)
        ui.general_stopOnError_checkBox.setChecked(general.get('stoponerror', '0') == '1')
        ui.general_assignBothVirtualCoresForSingleThread_checkBox.setChecked(
            general.get('assignbothvirtualcoresforsinglethread', '0') == '1')
        ui.general_skipCoreOnError_checkBox.setChecked(general.get('skipcoreonerror', '0') == '1')
        ui.general_restartTestProgramForEachCore_checkBox.setChecked(
            general.get('restarttestprogramforeachcore', '0') == '1')
        ui.general_suspendPeriodically_checkBox.setChecked(general.get('suspendperiodically', '0') == '1')
        ui.general_lookForWheaErros_checkBox.setChecked(general.get('lookforwheaerrors', '0') == '1')
        ui.general_treatWheaWarningAsError_checkBox.setChecked(
            general.get('treatwheawarningaserror', '0') == '1')
        ui.general_beepOnError_checkBox.setChecked(general.get('beeponerror', '0') == '1')
        ui.general_flashOnError_checkBox.setChecked(general.get('flashonerror', '0') == '1')
        
        # Use Config File (Checkbox and Line Edit)
        useconfigfile = general.get('useconfigfile', '')
        if useconfigfile:
            ui.general_useConfigFile_checkBox.setChecked(True)
            ui.general_useConfigFile_lineEdit.setText(useconfigfile)
        else:
            ui.general_useConfigFile_checkBox.setChecked(False)
            ui.general_useConfigFile_lineEdit.clear()
        
        # Runtime Per Core (Checkbox and Spinbox)
        runtimepercore = general.get('runtimepercore', 'Auto')
        if runtimepercore.lower() == 'auto':
            ui.general_runtimePerCore_checkBox_auto.setChecked(True)
        else:
            ui.general_runtimePerCore_checkBox_auto.setChecked(False)
            try:
                ui.general_runtimePerCore_spinBox.setValue(int(runtimepercore))
            except ValueError:
                ui.general_runtimePerCore_spinBox.setValue(1)  # Default
        
        # Core Test Order (Combobox and Line Edit)
        coretestorder = general.get('coretestorder', 'Default')
        predefined_orders = ['Default', 'Alternate', 'Random', 'Sequential', 'Custom']
        if coretestorder in predefined_orders:
            ui.general_coreTestOrder_comboBox.setCurrentText(coretestorder)
            if coretestorder == 'Custom':
                ui.general_coreTestOrder_lineEdit.setText(general.get('coretestorder', ''))
            else:
                ui.general_coreTestOrder_lineEdit.clear()
        else:
            ui.general_coreTestOrder_comboBox.setCurrentText('Custom')
            ui.general_coreTestOrder_lineEdit.setText(coretestorder)
        
        # Spinboxes (Integer settings)
        try:
            ui.general_maxIterations_spinBox.setValue(int(general.get('maxiterations', '1')))
            ui.general_delayBetweenCores_spinBox.setValue(int(general.get('delaybetweencores', '15')))
            ui.general_numberOfThreads_spinBox.setValue(int(general.get('numberofthreads', '1')))
        except ValueError:
            # Set defaults if conversion fails
            ui.general_maxIterations_spinBox.setValue(1)
            ui.general_delayBetweenCores_spinBox.setValue(15)
            ui.general_numberOfThreads_spinBox.setValue(1)
        
        # Cores to Ignore (Line Edit)
        ui.general_coresToIgnore_lineEdit.setText(general.get('corestoignore', ''))
    else:
        # If [General] section is missing, apply default GUI settings
        ui.general_stressTestProgram_radioButton_prime95.setChecked(True)
        ui.general_stopOnError_checkBox.setChecked(False)
        # Other defaults can be set as needed

def apply_general_config(ui):
    """Update the [General] section in config.ini based on current GUI settings."""
    config = configparser.ConfigParser()
    config.read('config.ini')
    
    # Ensure the [General] section exists
    if 'General' not in config:
        config['General'] = {}
    general = config['General']
    
    # Stress Test Program (Radio Buttons)
    if ui.general_stressTestProgram_radioButton_prime95.isChecked():
        general['stresstestprogram'] = 'PRIME95'
    elif ui.general_stressTestProgram_radioButton_linpack.isChecked():
        general['stresstestprogram'] = 'LINPACK'
    elif ui.general_stressTestProgram_radioButton_aida64.isChecked():
        general['stresstestprogram'] = 'AIDA64'
    elif ui.general_stressTestProgram_radioButton_ycruncher.isChecked():
        general['stresstestprogram'] = 'YCRUNCHER'
    elif ui.general_stressTestProgram_radioButton_ycruncher_old.isChecked():
        general['stresstestprogram'] = 'YCRUNCHER_OLD'
    
    # Checkboxes (Boolean settings)
    general['stoponerror'] = '1' if ui.general_stopOnError_checkBox.isChecked() else '0'
    general['assignbothvirtualcoresforsinglethread'] = '1' if ui.general_assignBothVirtualCoresForSingleThread_checkBox.isChecked() else '0'
    general['skipcoreonerror'] = '1' if ui.general_skipCoreOnError_checkBox.isChecked() else '0'
    general['restarttestprogramforeachcore'] = '1' if ui.general_restartTestProgramForEachCore_checkBox.isChecked() else '0'
    general['suspendperiodically'] = '1' if ui.general_suspendPeriodically_checkBox.isChecked() else '0'
    general['lookforwheaerrors'] = '1' if ui.general_lookForWheaErros_checkBox.isChecked() else '0'
    general['treatwheawarningaserror'] = '1' if ui.general_treatWheaWarningAsError_checkBox.isChecked() else '0'
    general['beeponerror'] = '1' if ui.general_beepOnError_checkBox.isChecked() else '0'
    general['flashonerror'] = '1' if ui.general_flashOnError_checkBox.isChecked() else '0'
    
    # Use Config File (Checkbox and Line Edit)
    if ui.general_useConfigFile_checkBox.isChecked():
        general['useconfigfile'] = ui.general_useConfigFile_lineEdit.text()
    else:
        general['useconfigfile'] = ''
    
    # Runtime Per Core (Checkbox and Spinbox)
    if ui.general_runtimePerCore_checkBox_auto.isChecked():
        general['runtimepercore'] = 'Auto'
    else:
        general['runtimepercore'] = str(ui.general_runtimePerCore_spinBox.value())
    
    # Core Test Order (Combobox and Line Edit)
    if ui.general_coreTestOrder_comboBox.currentText() == 'Custom':
        general['coretestorder'] = ui.general_coreTestOrder_lineEdit.text()
    else:
        general['coretestorder'] = ui.general_coreTestOrder_comboBox.currentText()
    
    # Spinboxes (Integer settings)
    general['maxiterations'] = str(ui.general_maxIterations_spinBox.value())
    general['delaybetweencores'] = str(ui.general_delayBetweenCores_spinBox.value())
    general['numberofthreads'] = str(ui.general_numberOfThreads_spinBox.value())
    
    # Cores to Ignore (Line Edit)
    general['corestoignore'] = ui.general_coresToIgnore_lineEdit.text()
    
    # Write the updated configuration back to config.ini
    with open('config.ini', 'w') as configfile:
        config.write(configfile)
