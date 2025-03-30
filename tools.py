import os
import subprocess
import ctypes

def launch_boost_tester():
    """Launch BoostTester.sp00n.exe from the tools folder."""
    try:
        os.startfile(os.path.join('tools', 'BoostTester.sp00n.exe'))
    except Exception as e:
        print(f"Error launching BoostTester: {e}")

def launch_pbo2_tuner():
    """Launch PBO2Tuner.exe from the PBO2Tuner folder within tools."""
    try:
        os.startfile(os.path.join('tools', 'PBO2Tuner', 'PBO2Tuner.exe'))
    except Exception as e:
        print(f"Error launching PBO2Tuner: {e}")

def launch_intel_voltage_control():
    """Launch IntelVoltageControl.exe from the IntelVoltageControl folder within tools."""
    try:
        os.startfile(os.path.join('tools', 'IntelVoltageControl', 'IntelVoltageControl.exe'))
    except Exception as e:
        print(f"Error launching IntelVoltageControl: {e}")

def launch_apic_ids():
    """Launch APICID.exe from the tools folder and open APICID.txt after it finishes."""
    try:
        apicid_exe_path = os.path.join('tools', 'APICID.exe')
        # Run APICID.exe and wait for it to complete
        subprocess.run([apicid_exe_path], check=True)
        apicid_txt_path = os.path.join('tools', 'APICID.txt')
        # Check if APICID.txt exists, then open it
        if os.path.exists(apicid_txt_path):
            os.startfile(apicid_txt_path)
        else:
            print("APICID.txt not found")
    except subprocess.CalledProcessError as e:
        print(f"APICID.exe failed with return code {e.returncode}")
    except Exception as e:
        print(f"Error: {e}")

def launch_core_tuner_x():
    """Launch CoreTunerX.exe from the tools folder."""
    try:
        os.startfile(os.path.join('tools', 'CoreTunerX.exe'))
    except Exception as e:
        print(f"Error launching CoreTunerX: {e}")

def launch_enable_performance_counters():
    """Launch enable_performance_counter.bat from the tools folder with administrator privileges."""
    try:
        bat_path = os.path.join("tools", "enable_performance_counter.bat")
        # Use ShellExecuteW with 'runas' to run the batch file as administrator
        ctypes.windll.shell32.ShellExecuteW(None, "runas", "cmd.exe", f'/c "{bat_path}"', None, 1)
    except Exception as e:
        print(f"Error launching enable_performance_counter.bat: {e}")

def open_helpers_folder():
    """Open the helpers folder in the file explorer."""
    try:
        os.startfile('helpers')
    except Exception as e:
        print(f"Error opening helpers folder: {e}")
