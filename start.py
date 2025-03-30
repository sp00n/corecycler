import sys
import os
from PyQt6.QtWidgets import QApplication, QMainWindow, QMessageBox
from mainwindow import Ui_MainWindow

def run_corecycler(parent):
    """
    Attempts to run the 'Run CoreCycler.bat' file located in the script's directory.
    Displays an error message in the GUI if the file is not found or execution fails.
    
    Args:
        parent: The main window instance, used as the parent for error message dialogs.
    """
    # Get the directory where start.py is located
    script_dir = os.path.dirname(os.path.abspath(__file__))
    # Construct the full path to the batch file
    batch_file = os.path.join(script_dir, 'Run CoreCycler.bat')
    
    # Check if the batch file exists
    if not os.path.exists(batch_file):
        QMessageBox.critical(parent, "Error", f"Batch file not found: {batch_file}")
        return
    
    # Try to execute the batch file
    try:
        os.startfile(batch_file)
    except Exception as e:
        QMessageBox.critical(parent, "Error", f"Error running CoreCycler: {e}")

if __name__ == "__main__":
    # Initialize the PyQt6 application
    app = QApplication(sys.argv)
    
    # Create the main window
    MainWindow = QMainWindow()
    
    # Set up the UI from mainwindow.py
    ui = Ui_MainWindow()
    ui.setupUi(MainWindow)
    
    # Connect the start_test_pushButton's clicked signal to the run_corecycler function
    ui.start_test_pushButton.clicked.connect(lambda: run_corecycler(MainWindow))
    
    # Show the main window
    MainWindow.show()
    
    # Run the application event loop
    sys.exit(app.exec())
