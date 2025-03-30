import configparser

def load_ycruncher_config(ui):
    """
    Load settings from the [yCruncher] section of config.ini into the GUI.

    Args:
        ui: The GUI object containing the widgets to be updated.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')

    if 'yCruncher' in config:
        ycruncher = config['yCruncher']

        # 1. Load mode
        mode = ycruncher.get('mode', '04-P4P')  # Default to '04-P4P' if not specified
        ui.ycruncher_mode_spinBox.setCurrentText(mode)

        # 2. Load tests based on stress test program selection
        stress_test_program = config['General'].get('stresstestprogram', '').lower()
        tests_str = ycruncher.get('tests', '')
        tests = [test.strip() for test in tests_str.split(',') if test.strip()]

        if 'ycruncher_old' in stress_test_program:
            # Map for old tests
            old_tests_map = {
                'BKT': ui.ycruncher_old_tests_bkt_checkBox,
                'BBP': ui.ycruncher_old_tests_bbp_checkBox,
                'SFT': ui.ycruncher_old_tests_sft_checkBox,
                'FFT': ui.ycruncher_old_tests_fft_checkBox,
                'N32': ui.ycruncher_old_tests_n32_checkBox,
                'N64': ui.ycruncher_old_tests_n64_checkBox,
                'HNT': ui.ycruncher_old_tests_hnt_checkBox,
                'VST': ui.ycruncher_old_tests_vst_checkBox,
                'C17': ui.ycruncher_old_tests_c17_checkBox,
            }
            for test, checkbox in old_tests_map.items():
                checkbox.setChecked(test in tests)
        else:
            # Map for regular tests
            tests_map = {
                'BKT': ui.ycruncher_tests_bkt_checkBox,
                'BBP': ui.ycruncher_tests_bbp_checkBox,
                'SFT': ui.ycruncher_tests_sft_checkBox,
                'SFTv4': ui.ycruncher_tests_sftv4_checkBox,
                'SNT': ui.ycruncher_tests_snt_checkBox,
                'SVT': ui.ycruncher_tests_svt_checkBox,
                'FFT': ui.ycruncher_tests_fft_checkBox,
                'FFTv4': ui.ycruncher_tests_fftv4_checkBox,
                'N63': ui.ycruncher_tests_n63_checkBox,
                'VT3': ui.ycruncher_tests_vt3_checkBox,
            }
            for test, checkbox in tests_map.items():
                checkbox.setChecked(test in tests)

        # 3. Load testDuration
        test_duration = ycruncher.get('testduration', '60')  # Default to 60 seconds
        try:
            ui.ycruncher_testDuration_spinBox.setValue(int(test_duration))
        except ValueError:
            ui.ycruncher_testDuration_spinBox.setValue(60)

        # 4. Load memory
        memory = ycruncher.get('memory', 'Default')
        if memory.lower() == 'default':
            ui.ycruncher_memory_default_checkBox.setChecked(True)
            ui.ycruncher_memory_doubleSpinBox.setEnabled(False)  # Disable spinbox when default
        else:
            ui.ycruncher_memory_default_checkBox.setChecked(False)
            ui.ycruncher_memory_doubleSpinBox.setEnabled(True)
            try:
                ui.ycruncher_memory_doubleSpinBox.setValue(float(memory))
            except ValueError:
                ui.ycruncher_memory_doubleSpinBox.setValue(0.0)

        # 5. Load enableYcruncherLoggingWrapper
        logging_wrapper = ycruncher.get('enableycruncherloggingwrapper', '0')
        ui.ycruncher_enableYcruncherLoggingWrapper_checkBox.setChecked(logging_wrapper == '1')
    else:
        # Set default values if [yCruncher] section is missing
        ui.ycruncher_mode_spinBox.setCurrentText('04-P4P')
        # Uncheck all test checkboxes
        for checkbox in [
            ui.ycruncher_tests_bkt_checkBox, ui.ycruncher_tests_bbp_checkBox,
            ui.ycruncher_tests_sft_checkBox, ui.ycruncher_tests_sftv4_checkBox,
            ui.ycruncher_tests_snt_checkBox, ui.ycruncher_tests_svt_checkBox,
            ui.ycruncher_tests_fft_checkBox, ui.ycruncher_tests_fftv4_checkBox,
            ui.ycruncher_tests_n63_checkBox, ui.ycruncher_tests_vt3_checkBox,
            ui.ycruncher_old_tests_bkt_checkBox, ui.ycruncher_old_tests_bbp_checkBox,
            ui.ycruncher_old_tests_sft_checkBox, ui.ycruncher_old_tests_fft_checkBox,
            ui.ycruncher_old_tests_n32_checkBox, ui.ycruncher_old_tests_n64_checkBox,
            ui.ycruncher_old_tests_hnt_checkBox, ui.ycruncher_old_tests_vst_checkBox,
            ui.ycruncher_old_tests_c17_checkBox,
        ]:
            checkbox.setChecked(False)
        ui.ycruncher_testDuration_spinBox.setValue(60)
        ui.ycruncher_memory_default_checkBox.setChecked(True)
        ui.ycruncher_memory_doubleSpinBox.setValue(0.0)
        ui.ycruncher_memory_doubleSpinBox.setEnabled(False)
        ui.ycruncher_enableYcruncherLoggingWrapper_checkBox.setChecked(False)

def apply_ycruncher_config(ui):
    """
    Apply current GUI settings to the [yCruncher] section of config.ini.

    Args:
        ui: The GUI object containing the widgets with current values.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')

    # Ensure [yCruncher] section exists
    if 'yCruncher' not in config:
        config['yCruncher'] = {}

    ycruncher = config['yCruncher']

    # 1. Apply mode
    ycruncher['mode'] = ui.ycruncher_mode_spinBox.currentText()

    # 2. Apply tests based on stress test program selection
    stress_test_program = ''
    if ui.general_stressTestProgram_radioButton_ycruncher.isChecked():
        stress_test_program = 'ycruncher'
    elif ui.general_stressTestProgram_radioButton_ycruncher_old.isChecked():
        stress_test_program = 'ycruncher_old'

    tests = []
    if stress_test_program == 'ycruncher_old':
        old_tests_map = {
            ui.ycruncher_old_tests_bkt_checkBox: 'BKT',
            ui.ycruncher_old_tests_bbp_checkBox: 'BBP',
            ui.ycruncher_old_tests_sft_checkBox: 'SFT',
            ui.ycruncher_old_tests_fft_checkBox: 'FFT',
            ui.ycruncher_old_tests_n32_checkBox: 'N32',
            ui.ycruncher_old_tests_n64_checkBox: 'N64',
            ui.ycruncher_old_tests_hnt_checkBox: 'HNT',
            ui.ycruncher_old_tests_vst_checkBox: 'VST',
            ui.ycruncher_old_tests_c17_checkBox: 'C17',
        }
        for checkbox, test in old_tests_map.items():
            if checkbox.isChecked():
                tests.append(test)
    else:
        tests_map = {
            ui.ycruncher_tests_bkt_checkBox: 'BKT',
            ui.ycruncher_tests_bbp_checkBox: 'BBP',
            ui.ycruncher_tests_sft_checkBox: 'SFT',
            ui.ycruncher_tests_sftv4_checkBox: 'SFTv4',
            ui.ycruncher_tests_snt_checkBox: 'SNT',
            ui.ycruncher_tests_svt_checkBox: 'SVT',
            ui.ycruncher_tests_fft_checkBox: 'FFT',
            ui.ycruncher_tests_fftv4_checkBox: 'FFTv4',
            ui.ycruncher_tests_n63_checkBox: 'N63',
            ui.ycruncher_tests_vt3_checkBox: 'VT3',
        }
        for checkbox, test in tests_map.items():
            if checkbox.isChecked():
                tests.append(test)
    ycruncher['tests'] = ', '.join(tests)

    # 3. Apply testDuration
    ycruncher['testduration'] = str(ui.ycruncher_testDuration_spinBox.value())

    # 4. Apply memory
    if ui.ycruncher_memory_default_checkBox.isChecked():
        ycruncher['memory'] = 'Default'
    else:
        ycruncher['memory'] = str(ui.ycruncher_memory_doubleSpinBox.value())

    # 5. Apply enableYcruncherLoggingWrapper
    ycruncher['enableycruncherloggingwrapper'] = '1' if ui.ycruncher_enableYcruncherLoggingWrapper_checkBox.isChecked() else '0'

    # Write the updated config to file
    with open('config.ini', 'w') as configfile:
        config.write(configfile)
