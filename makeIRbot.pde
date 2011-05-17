#include <MenuBackend.h>
// *** IRremote Params
#include <IRremote.h>
#include <IRremoteInt.h>
const int IR_RECV_PIN = 3;
IRrecv irrecv(IR_RECV_PIN);
decode_results results;

// Serial Variables
int serialIndex = 0;
uint8_t serialIn[32];  // for incoming serial data 

// EEPROM
//#include <EEPROM.h>

// makeIRbot Variables
const float makeIRbot = 1.2;
uint8_t machineName[16];
unsigned long refreshLast = 0; // Used for tracking refresh intervals
unsigned long refreshInterval = 0; // Set by diferent displays
int currentPhase = 0; // Used by various actions that require multiple steps
uint8_t commandSent = 0x00;
uint8_t responseRecv = 0x00;
int responseLength = 0;
 /* Bit fields for status
  0  :  Connected
  1  :  Building
  2  :  Valid File
  3  :
  4  :
  5  :
  6  :
  7  : Debug Mode
*/
uint8_t flags = 0x00;

const uint8_t extIndex = 0x02;
uint8_t extTemp = 0x00;
const uint8_t extTargetIndex = 0x20;
uint8_t extTarget = 0x00;

const uint8_t hbpIndex = 0x1E;
uint8_t hbpTemp = 0x00;
const uint8_t hbpTargetIndex = 0x21;
uint8_t hbpTarget = 0x00;

uint8_t lastFile[12];
// .s3g file Extension
const uint8_t validExt[4] = {0x2E, 0x73, 0x33, 0x67}; // ".s3g"
// Position data [Axis][Bytes]
uint8_t currentPos[3][4] = {
  {0x00, 0x00, 0x00, 0x00},    // X
  {0x00, 0x00, 0x00, 0x00},    // Y
  {0x00, 0x00, 0x00, 0x00},    // Z
};
#define xSteps 11.8 // Stock Cupcake settings and pulleys
#define ySteps 11.8 // Stock Cupcake settings and pulleys
#define zSteps 320  // Stock Cupcake settings and pulleys

#include <LiquidCrystal.h>
const int numRows = 2;
const int numCols = 16;
LiquidCrystal lcd(12, 11, 5, 6, 7, 8);

void printTemp(uint8_t temp, int col, int row, int symbol) {
  lcd.setCursor(col, row);
  if(temp < 10) { lcd.print("00");}
  else if(temp < 100) { lcd.print("0");}
  lcd.print(temp, DEC);
  lcd.print((char) symbol);
}

void printPos(int axis, int row, int col) {
  lcd.setCursor(col, row);
  long steps = read32(axis);
  float decPos = 0;
  switch (axis) {
    case 0: decPos = steps / xSteps; break;
    case 1: decPos = steps / ySteps; break;
    case 2: decPos = steps / zSteps; break;
  }
  // Handle formatting negative numbers
  if (decPos < 0 && decPos > -10) {
    lcd.print(" ");  
  }
  else if (decPos < 10) {
    lcd.print("  ");
  }
  else if (decPos < 100) {
    lcd.print(" ");
  }
  lcd.println(decPos, DEC);
}

void validateFilename() {
  bitClear(flags, 2);
  // First char is NULL?
  if (lastFile[0] != 0x00) {
    // Ignore hidden dot files
    if (lastFile[0] != 0x2E) {
      for (int i = 0; i < 12; i++) {
        // Watch for the period signifying the file extension
        if (lastFile[i] == 0x2E) {
          // Can we match the entire file extension?
          if (lastFile[i+1] == validExt[1] && 
              lastFile[i+2] == validExt[2] && 
              lastFile[i+3] == validExt[3]) {
            bitSet(flags, 2);
          }
        }
      }
    }
  }
}

void printFilename() {
  clearLCD(1);
  lcd.setCursor(0, 1);
  
  if (lastFile[0] == 0x00) {
    lcd.print("<NULL>");
  }
  else {
    for (int i = 0; i < 12; i++) {
      if (lastFile[i] == 0x00) {break;}
      lcd.print(lastFile[i]);
    }
  }
  // Indicate valid file or not
  lcd.setCursor(numCols - 2, 1);
  if (bitRead(flags, 2)) {
    lcd.print("OK");
  }
  else {
    lcd.print("--");
  }
}

MenuBackend menu = MenuBackend(menuUseEvent,menuChangeEvent);
  //beneath is list of menu items needed to build the menu
  MenuItem m_connect =    MenuItem         ("1 Connect      >");
      MenuItem m_flags =      MenuItem     ("1 Flags       <>");
        MenuItem m_debug =      MenuItem   ("1 Debug       <>");
          MenuItem m_debugtog =   MenuItem ("1 Debug Toggle< ");
  MenuItem m_temps =      MenuItem         ("2 Temp         >");
    MenuItem m_extruder =   MenuItem       ("2 Set EXT Temp<>");
      MenuItem m_hbp =        MenuItem     ("2 Set HBP Temp< ");
  MenuItem m_file =       MenuItem         ("3 SD File      >");
    MenuItem m_build =      MenuItem       ("3 SD Play File< ");
  MenuItem m_pos =        MenuItem         ("4 Position     >");
    MenuItem m_readypos =   MenuItem       ("4 Ready Pos   < ");

//this function builds the menu and connects the correct items together
void menuSetup() {
  //add the file menu to the menu root
  menu.getRoot().add(m_connect); 
    //setup the settings menu item
    m_connect.addBefore(m_pos);
    m_connect.addAfter(m_temps);
      m_connect.addRight(m_flags);
        m_flags.addRight(m_debug);
          m_debug.addRight(m_debugtog);
    m_temps.addAfter(m_file);
      m_temps.addRight(m_extruder);
        m_extruder.addRight(m_hbp);
    m_file.addAfter(m_pos);
      m_file.addRight(m_build);
    m_pos.addAfter(m_connect);
      m_pos.addRight(m_readypos);
}

void menuUseEvent(MenuUseEvent used){
  if (used.item == m_connect) {
    // Only query machine if we are not connected already
    if (!bitRead(flags, 0)) {
      queryMachineName();
      delay(50);
    }
    infoDisplay();
  }  
  else if (used.item == m_flags) {
    flagDisplay();
  }
  else if (used.item == m_debug) {
    debugDisplay();
  }
  else if (used.item == m_debugtog) {
    // Toggle the debug mode on or off
    if (bitRead(flags, 7)) {
      bitClear(flags, 7);
    }
    else {
      bitSet(flags, 7);
    }
    menu.moveLeft();
  }
  else if (used.item == m_temps) {
    currentPhase++;
    switch (currentPhase) {
      case 1: getTemp(extIndex); break;
      case 2: getTemp(extTargetIndex); break;
      case 3: getTemp(hbpIndex); break;
      case 4: getTemp(hbpTargetIndex); break;
      default: currentPhase = 0; tempDisplay(); // Reset phase then update display
    }
  }
  else if (used.item == m_file) {
    if (lastFile[0] == 0x00) { // Initial setting, or last entry on SD card
      fetchFirstFilename();
    }
    else {
      fetchNextFilename();
    }
    delay(50);
    printFilename();
  }
  else if (used.item == m_build) {
    if (bitRead(flags, 2)) {
      playbackFile(lastFile);
      menu.moveLeft();
    }
    else {
      clearLCD(1);
      lcd.print("<Invalid>");
    }
  }
  else if (used.item == m_pos) {
    currentPhase++;
    switch (currentPhase) {
      case 1: getPosition(); break;
      default: currentPhase = 0; posDisplay();
    }
  }
  else if (used.item == m_readypos) {
    setPosition();
    menu.moveLeft();
  }
}

void menuChangeEvent(MenuChangeEvent changed) {
  clearLCD(0);
  lcd.print(changed.to.getName());
  
  refreshInterval = 0; // Always clear refresh interval when the menu changes
  currentPhase = 0; // Always set the current phase back to zero, as not all events have phases
  if (changed.to.getName() == m_connect) {
    refreshInterval = 500;
    infoDisplay();
  }
  else if (changed.to.getName() == m_debug) {
    refreshInterval = 500;
    debugDisplay();
  }
  else if (changed.to.getName() == m_flags) {
    refreshInterval = 100;
    flagDisplay();
  }
  else if (changed.to.getName() == m_temps) {
    refreshInterval = 250;
    tempDisplay();
  }
  else if (changed.to.getName() == m_file) {
    printFilename(); // Make sure the filename display is always updated
  }
  else if (changed.to.getName() == m_build) {
    if (!bitRead(flags, 2)) { // Valid filename?
      menu.moveLeft();
    }
  }
  else if (changed.to.getName() == m_pos) {
    refreshInterval = 500;
    posDisplay();
  }
  else if (changed.to.getName() == m_readypos) {
    //
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
  menu.use(); // Call the connect menu to initialize the connection
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
          case 0x04: // Position query
            {
              int ap = 3; // Start of axis data
              // Loop through each axis
              for (int i = 0; i < 3; i++) {
                // Loop through 4 bytes for each axis
                for (int x = 0; x < 4; x++) {
                  currentPos[i][x] = serialIn[ap];
                  ap++;
                }
              }
            }
            break;
            
          case 0x10: // Print file
            //
            break;
          case 0x0A: // Get temp from tool
            switch (currentPhase) {
              case 1: extTemp   = serialIn[3]; break;
              case 2: extTarget = serialIn[3]; break;
              case 3: hbpTemp   = serialIn[3]; break;
              case 4: hbpTarget = serialIn[3]; break;
            }
            break;
            
          case 0x0C:
            if(serialIn[2] == 0x01) {
              bitSet(flags, 0);
              for (int mn = 0; mn < 16; mn++) {
                machineName[mn] = serialIn[mn + 3];
              }
            }
            else {
              bitClear(flags, 0);
            }
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
            validateFilename();
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
              case 0x00: /*responseText = "<SUCCESS>";*/ break;
              case 0x01: responseText = "<NO CARD>"; break;
              case 0x02: responseText = "<INIT FAILED>"; break;
              case 0x03: responseText = "<PARTITION ???>"; break;
              case 0x04: responseText = "<FS UNKNOWN>"; break;
              case 0x05: responseText = "<ROOT DIR ???>"; break;
              case 0x06: responseText = "<CARD LOCKED>"; break;
              case 0x07: responseText = "<NO SUCH FILE>"; break;
            }
            break;
            
          // Normal response codes
          default:
            switch(responseRecv) {
              case 0x00: responseText = "<GENERIC ERROR>"; break;
              case 0x01: /*responseText = "<OK>";*/ break;
              case 0x02: responseText = "<BUFF OVERFLOW>"; break;
              case 0x03: responseText = "<CRC MISMATCH>"; break;
              case 0x04: responseText = "<QUERY OVERFLOW>"; break;
              default: responseText   = "<CMD UNKNOWN>";
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
        // Assume that we are no longer connected
        bitClear(flags, 0);
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
      // Refresh various displays
      if (refreshInterval > 0 ) {
        // Trigger refresh
        if (millis() - refreshLast > refreshInterval ) {
          refreshLast = millis();
          menu.use();
        }
      }
    }
  }
}

void debugDisplay() {
  lcd.setCursor(0, 1);
  for (int i = 0; i < responseLength; i++) {
    lcd.print(serialIn[i]);
  }
}

void infoDisplay() {
  lcd.setCursor(0,1);
  if (bitRead(flags, 0)) {
    for (int i = 0; i < 16; i++) {
      if (machineName[i] != 0x00) {
        lcd.print(machineName[i]);
      }
      else {
        lcd.print(" ");
      }
    }
  }
  else {
    lcd.print("<NO CONNECTION> ");
  }
}

void flagDisplay() {
  lcd.setCursor(0, 1);
  lcd.print("c"); lcd.print(bitRead(flags, 0));
  lcd.print("b"); lcd.print(bitRead(flags, 1));
  lcd.print("v"); lcd.print(bitRead(flags, 2));
  lcd.print("-"); lcd.print(bitRead(flags, 3));
  lcd.print("-"); lcd.print(bitRead(flags, 4));
  lcd.print("-"); lcd.print(bitRead(flags, 5));
  lcd.print("-"); lcd.print(bitRead(flags, 6));
  lcd.print("d"); lcd.print(bitRead(flags, 7));
}

void tempDisplay() {
  lcd.setCursor(0,0);
  lcd.print("    Ext     HBP ");
  printTemp(extTemp, 0, 1, 47);
  printTemp(extTarget, 4, 1, 223);
  printTemp(hbpTemp, 8, 1, 47);
  printTemp(hbpTarget, 12, 1, 223);
}

void posDisplay() {
  lcd.setCursor(0,0);
  lcd.print("  X    Y    Z   ");
  clearLCD(1);
  printPos(0, 1, 0);
  printPos(1, 1, 5);
  printPos(2, 1, 10);
}

void irButtonAction(decode_results *results) {
  int code = (int) results->value;
  if(code != -1) {
    switch(code) {
      case -32513: menu.moveUp(); break;    // Up Arrow
      case 18493: menu.moveDown(); break;   // Down Arrow
      case 25706: menu.moveLeft(); break;   // Left Arrow
      case 24620: menu.moveRight(); break;  // Right Arrow
      case -16257: menu.use(); break;       // OK/Select Arrow
      default:
        clearLCD(1);
        lcd.print("?IR:            ");
        lcd.setCursor(4, 1);
        lcd.print(code);
    }
  }
}

void queryMakerbotInfo() { // Fetch build name of machine (Cupcake)
  uint8_t data[]= {0x14, 0x18, 0x00};
  sendBytesWithCRC(data, sizeof(data));
}

void queryMachineName() { // Read 16 chars from EEPROM at Offset 32
  uint8_t data[] = {0x0C, 0x20, 0x00, 0x10};
  sendBytesWithCRC(data, sizeof(data));
}

void getTemp(uint8_t toolIndex) {
  uint8_t data[]= {0x0A, 0x00, toolIndex};
  sendBytesWithCRC(data, sizeof(data));
}

void fetchFirstFilename() {
  uint8_t data[]= {0x12, 0x01};
  sendBytesWithCRC(data, sizeof(data));
}

void fetchNextFilename() {
  uint8_t data[]= {0x12, 0x00};
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
  uint8_t data[] = {0x04};
  sendBytesWithCRC(data, 1);
}

void setPosition() { // Hardcoded to X0 Y0 Z15
  uint8_t data[] = {0x82, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC2, 0x12, 0x00, 0x00};
  sendBytesWithCRC(data, 13);
}

void sendBytesWithCRC(uint8_t *data, int len){
  uint8_t crc = 0x00;
  int length = len;
  int a;
  int fn = 1;
  commandSent = data[0];
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

uint32_t read32(int axis) {
  union {
    // AVR is little-endian
    int32_t a;
    struct {
      uint8_t data[4];
    } b;
  } shared;
  shared.b.data[0] = currentPos[axis][0];
  shared.b.data[1] = currentPos[axis][1];
  shared.b.data[2] = currentPos[axis][2];
  shared.b.data[3] = currentPos[axis][3];

  return shared.a;
}

void clearLCD(int row) {
  lcd.setCursor(0, row);
  for (int i = 0; i < numCols; i++) {
    lcd.print(" ");
  }
  lcd.setCursor(0, row);
}

