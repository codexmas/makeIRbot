#include <MenuBackend.h>
// *** IRremote Params
#include <IRremote.h>
#include <IRremoteInt.h>
const int IR_RECV_PIN = 3;
IRrecv irrecv(IR_RECV_PIN);
decode_results results;

// Serial Variables
int serialIndex = 0;
uint8_t serialIn[64];  // for incoming serial data 

// EEPROM
//#include <EEPROM.h>

// makeIRbot Variables
float makeIRbot = 1.01;
uint8_t commandSent = 0x00;
uint8_t responseRecv = 0x00;
int responseLength = 0;
boolean validFile = false;
uint8_t queryTool = 0x00;

uint8_t extIndex = 0x02;
uint8_t extTemp = 0x00;
//uint8_t extTarget = 0x00;

uint8_t hbpIndex = 0x1E;
uint8_t hbpTemp = 0x00;
//uint8_t hbpTarget = 0x00;

uint8_t lastFile[12];

uint8_t axisX = {0x00};    
uint8_t axisY = {0x00};
uint8_t axisZ = {0x00};

#include <LiquidCrystal.h>
const int numRows = 2;
const int numCols = 16;
LiquidCrystal lcd(12, 11, 5, 6, 7, 8);

void printTemp(uint8_t temp, int col, int row) {
  lcd.setCursor(col, row);
  if(temp < 10) { lcd.print("  ");}
  else if(temp < 100) { lcd.print(" ");}
  lcd.print(temp, DEC);
  lcd.print((char) 223);
}

void printPos(uint8_t temp, int col, int row) {
  lcd.setCursor(col, row);
  // Convert 4byte position
  lcd.print("--0.0");
}

// Return true if filename is printable
void printFilename(int output=1) {
  validFile = false;
  uint8_t valid[4] = {0x2E, 0x73, 0x33, 0x67}; // ".s3g"      
  if (output == 1) {
    clearLCD(1);
    lcd.setCursor(0, 1);
  }
  if (lastFile[0] == 0x00) {
    if (output == 1) {lcd.print("<NULL>"); }
  }
  else {
    for (int i = 0; i < responseLength; i++) {
      if (lastFile[i] == 0x00) { 
        uint8_t ext[4] = {
          lastFile[i - 4], lastFile[i - 3], lastFile[i - 2], lastFile[i - 1] };
        if (ext[0] == valid[0] && ext[1] == valid[1] && ext[2] == valid[2] && ext[3] == valid[3]) {
          validFile = true;
        }
        break; 
      }
      if (output == 1) {
        lcd.print(lastFile[i]);
      }
    }
  }
  if (output == 1) {
    lcd.setCursor(14, 1);
    if (validFile == true) {
      lcd.print("OK");
    }
    else {
      lcd.print("--");
    }
  }
}

MenuBackend menu = MenuBackend(menuUseEvent,menuChangeEvent);
  //beneath is list of menu items needed to build the menu
  MenuItem m_connect =    MenuItem       ("1 Connect      >");
    MenuItem m_debug =      MenuItem     ("1 Debug       < ");
  MenuItem m_temps =      MenuItem       ("2 Temp         >");
    MenuItem m_extruder =   MenuItem     ("2 Set EXT Temp<>");
      MenuItem m_hbp =        MenuItem   ("2 Set HBP Temp< ");
  MenuItem m_file =       MenuItem       ("3 SD File      >");
    MenuItem m_build =      MenuItem     ("3 SD Play File< ");
  MenuItem m_pos =        MenuItem       ("4 Position      ");

//this function builds the menu and connects the correct items together
void menuSetup() {
  //add the file menu to the menu root
  menu.getRoot().add(m_connect); 
    //setup the settings menu item
    m_connect.addBefore(m_pos);
    m_connect.addAfter(m_temps);
      m_connect.addRight(m_debug);
    m_temps.addAfter(m_file);
      m_temps.addRight(m_extruder);
        m_extruder.addRight(m_hbp);
    m_file.addAfter(m_pos);
      m_file.addRight(m_build);
    m_pos.addAfter(m_connect);
}

void menuUseEvent(MenuUseEvent used){
  clearLCD(0);
  lcd.print(used.item.getName());
  delay(100);
  if (used.item == m_connect) {
    queryMakerbotInfo();
    delay(30);
  }  
  else if (used.item == m_debug) {
    debugDisplay();
    delay(30);
  }
  else if (used.item == m_temps) {
    getTemp(extIndex);
    delay(30);
    getTemp(hbpIndex);
    delay(30);
  }
  else if (used.item == m_file) {
    if (lastFile[0] == 0x00) {
      fetchFirstFilename();
    }
    else {
      fetchNextFilename();
    }
    delay(30);
  }
  else if (used.item == m_build) {
    if (validFile) {
      menu.moveLeft();
      playbackFile(lastFile);
    }
    else {
      clearLCD(1);
      lcd.print("<Invalid>");
    }
  }
  else if (used.item == m_pos) {
    getPosition();
  }
}

void menuChangeEvent(MenuChangeEvent changed) {
  clearLCD(0);
  lcd.print(changed.to.getName());
  if(changed.to.getName() == m_build) {
    if(!validFile){
      menu.moveLeft();
    }
  }
}

void setup() {
  lcd.begin(numCols, numRows);
  lcd.clear();
  lcd.print("makeIRbot v");
  lcd.print(makeIRbot);
  menuSetup();
  menu.moveDown();
  irrecv.enableIRIn(); // Start the receiver
  Serial.begin(38400);
}

void loop() {  
  // Watch for Serial Data
  if (Serial.available() > 0) {
    delay(1); // Need delay to properly grab serial data
    serialIn[serialIndex++] = Serial.read();
  }
  else {
    if (serialIndex > 0) {
      if (serialIn[0] == 0xD5) {
        responseRecv = serialIn[2];
        switch(commandSent) {
          case 0x04:
          
            posDisplay();
            break;
            
          case 0x10: // Print file
          
            break;
          case 0x0A: // Get temp from tool
            extTemp = serialIn[3];
            hbpTemp = serialIn[9];
            tempDisplay();
            break;
          
          case 0x12: // Read filename from SD Card
            for (int cf = 0; cf < 12; cf++) {
              lastFile[cf] = 0x00;
            }
            for (int rf = 0; rf < 12; rf++) {
              if(serialIn[rf + 4] != 0x00) {
                lastFile[rf] = serialIn[rf + 4];
              }
              else {
                break;
              }
            }
            printFilename();
            break;
          
          default:
            // Pass through
            if(1) {}
        }  
        String responseText = "";
        // Deal with response codes
        switch(commandSent) {
          // SD Card response codes
          case 0x10:
          case 0x12:
            switch(serialIn[3]) {
              case 0x00:
                //responseText = "<SUCCESS>";
                break;
              case 0x01:
                responseText = "<NO CARD>";
                break;
              case 0x02:
                responseText = "<INIT FAILED>";
                break;
              case 0x03:
                responseText = "<PARTITION ???>";
                break;
              case 0x04:
                responseText = "<FS UNKNOWN>";
                break;
              case 0x05:
                responseText = "<ROOT DIR ???>";
                break;
              case 0x06:
                responseText = "<CARD LOCKED>";
                break;
              case 0x07:
                responseText = "<NO SUCH FILE>";
                break;
            }
            break;
            
          // Normal response codes
          default:
            switch(responseRecv) {
              case 0x00:
                responseText = "<GENERIC ERROR>";
                break;
              case 0x01:
                //responseText = "<OK>";
                break;
              case 0x02:
                responseText = "<BUFF OVERFLOW>";
                break;
              case 0x03:
                responseText = "<CRC MISMATCH>";
                break;
              case 0x04:
                responseText = "<QUERY OVERFLOW>";
                break;
              default:
                responseText = "<CMD UNKNOWN>";
            }
        }
        if (responseText != "") {
          clearLCD(1);
          lcd.print(responseText);
        }
      }
      else {
        // Other serial data
        responseRecv = 0xFF;
      }
      responseLength = serialIndex;
      serialIndex = 0;
    }
    else {
      // Watch for IR Codes
      if (irrecv.decode(&results)) {
        irButtonAction(&results);
        irrecv.resume(); // Receive the next value
      }
    }
  }
}

void debugDisplay() {
  lcd.clear();
  lcd.print("O:");
  lcd.print((int)commandSent);
  lcd.print(" I:");
  lcd.print((int) responseRecv);
  lcd.print(" P:");
  lcd.print((int) serialIn[1]);
  lcd.print(" ");
  lcd.print((int) serialIn[responseLength - 1]);
  lcd.setCursor(0, 1);
  for (int i = 0; i < responseLength; i++) {
    lcd.print(serialIn[i]);
  }
}

void tempDisplay() {
  lcd.setCursor(0,0);
  lcd.print("ExtruderPlatform");
  clearLCD(1);
  printTemp(extTemp, 2, 1);
  //printTemp(extTarget, 4, 1);
  printTemp(hbpTemp, 10, 1);
  //printTemp(hbpTarget, 12, 1);
}

void posDisplay() {
  lcd.setCursor(0,0);
  lcd.print("  X    Y    Z  ");
  clearLCD(1);
  printPos(axisX, 0, 1);
  printPos(axisY, 5, 1);
  printPos(axisZ, 10, 1);
}

void irButtonAction(decode_results *results) {
  int code = (int) results->value;
  if(code != -1) {
    switch(code) {
      // Up Arrow
      case -32513: menu.moveUp(); break;
      // Down Arrow
      case 18493: menu.moveDown(); break;
      // Left Arrow
      case 25706: menu.moveLeft(); break;
      // Right Arrow
      case 24620: menu.moveRight(); break;
      // OK/Select Arrow
      case -16257: menu.use(); break;

      default:
        clearLCD(1);
        lcd.print(code);
    }
  }
}

void queryMakerbotInfo() { // Fetch build name of machine (Cupcake)
  uint8_t data[]= {
    0x14, 0x18, 0x00  };
  sendBytesWithCRC(data, sizeof(data));
}

void queryMachineName() { // Read 16 chars from EEPROM at Offset 32
  uint8_t data[] = {
    0x0C, 0x20, 0x00, 0x10 };
  sendBytesWithCRC(data, sizeof(data));
}

void getTemp(uint8_t toolIndex) {
  uint8_t data[]= {
    0x0A, 0x00, toolIndex };
  sendBytesWithCRC(data, sizeof(data));
}

void fetchFirstFilename() {
  uint8_t data[]= {
    0x12, 0x01  };
  sendBytesWithCRC(data, sizeof(data));
}

void fetchNextFilename() {
  uint8_t data[]= {
    0x12, 0x00  };
  sendBytesWithCRC(data, sizeof(data));
}

void playbackFile(uint8_t *filename) {
  int i = 0;
  uint8_t data[12];
  data[0] = 0x10; // Build command code
  while(filename[i] != 0x00) {
    data[i + 1] = filename[i];
    i++;
  }
  data[i + 1] = 0x00; // Add null termination
  
  sendBytesWithCRC(data, i + 2);
}

void getPosition() {
  uint8_t data[] = {
    0x04 };
  sendBytesWithCRC(data, 1);
}

void sendBytesWithCRC(uint8_t *data, int len){
  uint8_t crc = 0x00;
  int length = len;
  int a;
  int fn = 1;
  commandSent = data[0];
  queryTool = 0x00;
  switch(commandSent) {
    case 0x0A:
      queryTool = data[2];
      break;
  }
  Serial.print(0xD5, BYTE);    // Send header Identifier byte
  Serial.print(length, BYTE);  // Send payload length
  // Send Payload
  for(int p = 0; p < length; p++){
    Serial.print(data[p], BYTE);
  }

  // Send calculated CRC
  for(a = 0; a < length; a++) {
    delay(1);
    crc = calculateCRC(crc, data[a]);
  }
  Serial.print(crc, BYTE);
}

uint8_t calculateCRC (uint8_t crc, uint8_t data) {
  uint8_t cc;
  crc = crc ^ data;
  for (cc = 0; cc < 8; cc++) {
    if (crc & 0x01)
      crc = (crc >> 1) ^ 0x8C;
    else
      crc >>= 1;
  }
  return crc;
}

void clearLCD(int row) {
  lcd.setCursor(0, row);
  lcd.print("                ");
  lcd.setCursor(0, row);
}

