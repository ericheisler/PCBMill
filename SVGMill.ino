/**
 *  
 *  A slightly modified version of the SVG plotter code
 *
 *  Update:   Added drilling capability
 *  2014-4-1  Added cut depth adjustment via serial
 *            Added parameter modification via serial
 *            Made math more accurate and efficient
 *  
 *  NOTE: This is specific to my setup, but you can modify it to match yours.
 *        Change the function "oneStep" to move your steppers/servos.
 *        You will certainly have to change the parameters below, labeled as
 *        "Set these variables to match your setup".
 *  
 *  This complements the SVG image reader.
 *  Recieves coordinate data via serial.
 *  Controls motors for x and y axes as well as raising and lowering a pen.
 *  The exact details of the motor control will have to be changed
 *  to match your setup.
 *  
 *  Copyright 2014 Eric Heisler
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 3 as published by
 *  the Free Software Foundation.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *  
 *  The SVG vector graphics file type is specified by and belongs to W3C
 */

////////////////////////////////////////////////////////////////////////////////
// Set these variables to match your setup                                  ////
////////////////////////////////////////////////////////////////////////////////
// step parameters                                                          ////
//float stepSize[2] = {0.018405, 0.114583}; // mm per step [x, y]       ////
float stepSize[2] = {56.889, 9.467}; // steps per mm [x, y]       ////
int fastDelay[3] = {3, 18, 25}; // determines movement speed by             ////
int slowDelay[3] = {30, 180, 50}; // delaying ms after each step            ////
// enable and phase pins for each motor                                     ////
// this is for two-winding bipolar steppers                                 ////
//const uint8_t e1[2] = {13, 9}; // winding 1 [x, y]                          ////
//const uint8_t p1[2] = {12, 8};                                              ////
//const uint8_t e2[2] = {11, 7}; // winding 2                                 ////
//const uint8_t p2[2] = {10, 6};                                              ////
// for breadboard version                                                   ////
const uint8_t e1[2] = {14, 12}; // winding 1 [x, y]                         ////
const uint8_t p1[2] = {13, 11};                                             ////
const uint8_t e2[2] = {16, 10}; // winding 2                                ////
const uint8_t p2[2] = {15, 9};                                              ////
// z axis control pins                                                      ////
// this is a 4 winding unipolar stepper                                     ////
//const uint8_t zpins[4] = {2,3,4,5};                                         ////
// for breadboard version                                                   ////
const uint8_t zpins[4] = {5,6,7,8};                                         ////
// this is the amount to lift the bit away from the piece to move           ////
int zlift = 200;
// this is the drill depth
int drill = 400;
// the buttons for calibrating Z
const uint8_t blackButton = 4;
const uint8_t redButton = 3;
// limit pins                                                               ////
const boolean hasLimits = false;                                            ////
const uint8_t xlimitPin = 255; // If you have limit switches                ////
const uint8_t ylimitPin = 255;                                              ////
// the serial rate                                                          ////
#define SRATE 9600
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

// the current position
float mmPerStep[2] = {1.0/stepSize[0], 1.0/stepSize[1]};
float posmm[2];
int poss[2];
int posz;
// the current motor states
uint8_t mstate[2]; // 0=+off 1=+- 2=off- 3=-- 4=-off 5=-+ 6=off+ 7=++
uint8_t zstate; // 0, 1, 2, 3

// if it is touching the limits
volatile boolean xlimit, ylimit;

// used for serial communication
char inputchars[10];
int charcount;
float newx, newy;
int sign;
boolean started;

boolean zdown;
// Z depth calibration
// 0=begin, push black to lower slowly. Go until touching
// 1=manual, click red to lower one step at a time. Sets cut depth
// 2=finished, click black to finish calibrating. Backs off by ZLIFT
uint8_t zcal; 
int zTouch;
int zCut;

void setup(){
  pinMode(e1[0], OUTPUT);
  pinMode(e1[1], OUTPUT);
  pinMode(e2[0], OUTPUT);
  pinMode(e2[1], OUTPUT);
  pinMode(p1[0], OUTPUT);
  pinMode(p1[1], OUTPUT);
  pinMode(p2[0], OUTPUT);
  pinMode(p2[1], OUTPUT);
  
  pinMode(zpins[0], OUTPUT);
  pinMode(zpins[1], OUTPUT);
  pinMode(zpins[2], OUTPUT);
  pinMode(zpins[3], OUTPUT);
  
  pinMode(blackButton, INPUT_PULLUP);
  pinMode(redButton, INPUT_PULLUP);
  
  if(hasLimits){
    pinMode(xlimitPin, OUTPUT);
    pinMode(ylimitPin, OUTPUT);
  }
  
  // put x,y motors in state 0 = +off
  mstate[0] = 0;
  mstate[1] = 0;
  posmm[0] = 0.0;
  posmm[1] = 0.0;
  poss[0] = 0;
  poss[1] = 0;
  digitalWrite(e1[0], LOW);
  digitalWrite(e1[1], LOW);
  
  digitalWrite(e2[0], HIGH);
  digitalWrite(e2[1], HIGH);
  
  digitalWrite(p1[0], HIGH);
  digitalWrite(p1[1], HIGH);
  
  digitalWrite(p2[0], HIGH);
  digitalWrite(p2[1], HIGH);
  
  // put z motor in state 0
  zstate = 0;
  zcal = 0;
  posz = 0;
  digitalWrite(zpins[0], HIGH);
  digitalWrite(zpins[1], LOW);
  digitalWrite(zpins[2], LOW);
  digitalWrite(zpins[3], LOW);
  
  delay(300); // give motors and such a chance to settle
  
  xlimit = false;
  ylimit = false;
  
  // for limit switches
  if(hasLimits){
    attachInterrupt(0, hitXLimit, CHANGE);
    attachInterrupt(1, hitYLimit, CHANGE);
    
    goHome();
    posmm[0] = 0.0;
    posmm[1] = 0.0;
    poss[0] = 0;
    poss[1] = 0;
    
    findCenter();
  }
  
  // set up the serial stuff
  Serial.begin(SRATE);
  started = false;
  zdown = false;
  
  // wait for processing to connect
  bool waiting = true;
  while(waiting){
    if((millis()/1000)%2){
      digitalWrite(13, HIGH);
    }else{
      digitalWrite(13, LOW);
    }
    if(Serial.available()>0){
      if(Serial.read() == '#'){
        Serial.write('@');
        waiting = false;
      }
    }
  }
  digitalWrite(13, LOW);
  // flush serial
  while(Serial.available()>0){
    Serial.read();
  }
  
  // calibrate Z axis and send ready signal
  calibrateZ();
  Serial.write('Z');
}


void loop() {
  // wait for data to come
  while(Serial.available() < 1);
  
  // the char '#' is a comm check. reply with '@'
  // start if the char 'S' is sent, finish if 'T' is sent
  if(Serial.peek() == '#'){
    Serial.read();
    Serial.write('@');
  }else if(Serial.peek() == 'S'){
    // drawing started
    started = true;
    zdown = false;
    Serial.read();
  }else if(Serial.peek() == 'T'){
    // drawing finished
    started = false;
    Serial.read();
    raiseZ(zlift);
    zdown = false;
    drawLine(0.0, 0.0);
    posmm[0] = 0.0;
    posmm[1] = 0.0;
    poss[0] = 0;
    poss[1] = 0;
  }else if(Serial.peek() == 'A'){
    // raise Z
    Serial.read();
    if(zdown){
      raiseZ(zlift);
      zdown = false;
    }
    Serial.write(7);
  }else if(Serial.peek() == 'Z'){
    // lower Z
    Serial.read();
    if(!zdown){
      lowerZ(zlift);
      zdown = true;
    }
    Serial.write(7);
  }else if(Serial.peek() == 'D'){
    // lower then raise Z by amount DRILL
    Serial.read();
    lowerZ(drill);
    raiseZ(drill);
    Serial.write(8);
  }else if(Serial.peek() == 'H'){
    // change Z by this amount
    Serial.read();
    int amount = int(receiveNumber());
    if(amount > 0){
      raiseZ(amount);
    }else{
      lowerZ(-amount);
    }
    Serial.write(9);
  }else if(Serial.peek() == 'P'){
    // change some parameter
    Serial.read();
    changeParameter();
    Serial.write(9);
  }else if(started){
    // if there is some serial data, read it, parse it, use it
    newx = receiveNumber();
    // wait for the y data
    newy = receiveNumber();
    // now we have newx and newy. 
    drawLine(newx, newy);
  }else{
    // it was some unexpected transmission
    // clear it
    Serial.read();
  }
  
}

float receiveNumber(){
  boolean complete = false;
  char tmpchar;
  charcount = 0;
  float thenumber = 0;
  sign = 1;
  while(!complete){
    // wait for data
    while(Serial.available() < 1);
    tmpchar = Serial.read();
    if(tmpchar == '.'){ // signals end of number
      complete = true;
      continue;
    }
    if(tmpchar == '-'){
      sign = -1;
    }else{
      thenumber = thenumber*10.0 + tmpchar-'0';
    }
    charcount++;
  }
  thenumber = thenumber*sign/10000.0;
  Serial.write(charcount); // send verification byte
  return thenumber;
}

void calibrateZ(){
  while(zcal == 0){
    if(!digitalRead(redButton)){
      zcal = 1;
    }
    if(!digitalRead(blackButton)){
      lowerZ(1);
    }
  }
  zTouch = posz;
  delay(100);
  while(zcal == 1){
    if(!digitalRead(blackButton)){
      zcal = 2;
    }
    if(!digitalRead(redButton)){
      lowerZ(1);
      delay(70);
      // wait for release. If black button is pushed while holding red, this is z up position
      while(!digitalRead(redButton)){
        if(!digitalRead(blackButton)){
          zcal = 2;
          raiseZ(1);
          zCut = posz - zlift;
          zdown = false;
          return;
        }
      }
      delay(70);
    }
  }
  zCut = posz;
  raiseZ(zlift);
  zdown = false;
}

void raiseZ(int s){
  while(s){
    s--;
    posz++;
    if(zstate == 0){
      digitalWrite(zpins[1], HIGH);
      digitalWrite(zpins[0], LOW);
      zstate = 1;
    }else if(zstate == 1){
      digitalWrite(zpins[2], HIGH);
      digitalWrite(zpins[1], LOW);
      zstate = 2;
    }else if(zstate == 2){
      digitalWrite(zpins[3], HIGH);
      digitalWrite(zpins[2], LOW);
      zstate = 3;
    }else if(zstate == 3){
      digitalWrite(zpins[0], HIGH);
      digitalWrite(zpins[3], LOW);
      zstate = 0;
    }
    delay(fastDelay[2]);
  }
}

void lowerZ(int s){
  while(s){
    s--;
    posz --;
    if(zstate == 0){
      digitalWrite(zpins[3], HIGH);
      digitalWrite(zpins[0], LOW);
      zstate = 3;
    }else if(zstate == 1){
      digitalWrite(zpins[0], HIGH);
      digitalWrite(zpins[1], LOW);
      zstate = 0;
    }else if(zstate == 2){
      digitalWrite(zpins[1], HIGH);
      digitalWrite(zpins[2], LOW);
      zstate = 1;
    }else if(zstate == 3){
      digitalWrite(zpins[2], HIGH);
      digitalWrite(zpins[3], LOW);
      zstate = 2;
    }
    delay(slowDelay[2]);
  }
}

// changes a specified parameter
void changeParameter(){
  // the next char determines the parameter
  while(Serial.available() < 1); //wait
  if(Serial.peek() == 'x'){
    // the x step size
    Serial.read();
    stepSize[0] = receiveNumber();
    mmPerStep[0] = 1.0/stepSize[0];
  }else if(Serial.peek() == 'y'){
    // the y step size
    Serial.read();
    stepSize[1] = receiveNumber();
    mmPerStep[1] = 1.0/stepSize[1];
  }else if(Serial.peek() == 'f'){
    // fast delay
    Serial.read();
    fastDelay[0] = int(receiveNumber());
    fastDelay[1] = int(receiveNumber());
    fastDelay[2] = int(receiveNumber());
  }else if(Serial.peek() == 's'){
    // slow delay
    Serial.read();
    slowDelay[0] = int(receiveNumber());
    slowDelay[1] = int(receiveNumber());
    slowDelay[2] = int(receiveNumber());
  }else if(Serial.peek() == 'z'){
    // zlift
    Serial.read();
    zlift = int(receiveNumber());
  }else if(Serial.peek() == 'd'){
    // drill
    Serial.read();
    drill = int(receiveNumber());
  }
}

/*
* moves in a straight line from the current position
* to the point (x2, y2)
*/
void drawLine(float x2, float y2){
  long xSteps, ySteps;
  int8_t xdir, ydir;
  float slope;
  long dx, dy;
  // determine the direction and number of steps
  xdir = 1;
  if(x2-posmm[0] < 0 ) xdir = -1;
  xSteps = long(x2*stepSize[0] - posmm[0]*stepSize[0] + 0.5*xdir);
  
  ydir = 1;
  if(y2-posmm[1] < 0) ydir = -1;
  ySteps = long(y2*stepSize[1] - posmm[1]*stepSize[1] + 0.5*ydir);
  
  if(xSteps*xdir > 0){
    slope = ySteps*1.0/(1.0*xSteps)*ydir*xdir;
  }else{
    slope = 100000;
  }
  dx = 0;
  dy = 0;

  if(xSteps*xdir > ySteps*ydir){
    while(dx < xSteps*xdir){
      if(hasLimits){
        if(xlimit || ylimit){
          // we hit a limit. back off the switch, and return
          oneStep(0, -xdir);
          oneStep(0, -xdir);
          oneStep(1, -ydir);
          oneStep(1, -ydir);
          return;
        }
      }
      // move one x step at a time
      dx++;
      oneStep(0, xdir);
      // if needed, move y one step
      if(ySteps*ydir > 0 && (slope*dx)-0.5 > dy){
        dy++;
        oneStep(1, ydir);
      }
    }
  }
  else{
    while(dy < ySteps*ydir){
      if(hasLimits){
        if(xlimit || ylimit){
          // we hit a limit. back off the switch, and return
          oneStep(0, -xdir);
          oneStep(0, -xdir);
          oneStep(1, -ydir);
          oneStep(1, -ydir);
          return;
        }
      }
      // move one y step at a time
      dy++;
      oneStep(1, ydir);
      // if needed, move x one step
      if(xSteps*xdir > 0 && dy > slope*(dx+0.5)){
        dx++;
        oneStep(0, xdir);
      }
    }
  }
  // finish up any remaining steps
  while(dx < xSteps*xdir){
    // move one x step at a time
    dx++;
    oneStep(0, xdir);
  }
  while(dy < ySteps*ydir){
    // move one y step at a time
    dy++;
    oneStep(1, ydir);
  }
  // at this point we have drawn the line
}

void oneStep(int m, int dir){
  // make one step with motor number m in direction dir
  // then delay depending on zdown
  // 0=+off 1=+- 2=off- 3=-- 4=-off 5=-+ 6=off+ 7=++
  if(dir > 0){
    poss[m]++;
    posmm[m] += mmPerStep[m];
    if(mstate[m] ==0){
      digitalWrite(p2[m], LOW);
      digitalWrite(e2[m], LOW);
      mstate[m] = 1;
    }
    else if(mstate[m] ==1){
      digitalWrite(e1[m], HIGH);
      mstate[m] = 2;
    }
    else if(mstate[m] ==2){
      digitalWrite(p1[m], LOW);
      digitalWrite(e1[m], LOW);
      mstate[m] = 3;
    }
    else if(mstate[m] ==3){
      digitalWrite(e2[m], HIGH);
      mstate[m] = 4;
    }
    else if(mstate[m] ==4){
      digitalWrite(p2[m], HIGH);
      digitalWrite(e2[m], LOW);
      mstate[m] = 5;
    }
    else if(mstate[m] ==5){
      digitalWrite(e1[m], HIGH);
      mstate[m] = 6;
    }
    else if(mstate[m] ==6){
      digitalWrite(p1[m], HIGH);
      digitalWrite(e1[m], LOW);
      mstate[m] = 7;
    }
    else if(mstate[m] ==7){
      digitalWrite(e2[m], HIGH);
      mstate[m] = 0;
    }
  }
  else{
    // 0=+off 1=+- 2=off- 3=-- 4=-off 5=-+ 6=off+ 7=++
    poss[m]--;
    posmm[m] -= mmPerStep[m];
    if(mstate[m] ==0){
      digitalWrite(p2[m], HIGH);
      digitalWrite(e2[m], LOW);
      mstate[m] = 7;
    }
    else if(mstate[m] ==1){
      digitalWrite(e2[m], HIGH);
      mstate[m] = 0;
    }
    else if(mstate[m] ==2){
      digitalWrite(p1[m], HIGH);
      digitalWrite(e1[m], LOW);
      mstate[m] = 1;
    }
    else if(mstate[m] ==3){
      digitalWrite(e1[m], HIGH);
      mstate[m] = 2;
    }
    else if(mstate[m] ==4){
      digitalWrite(p2[m], LOW);
      digitalWrite(e2[m], LOW);
      mstate[m] = 3;
    }
    else if(mstate[m] ==5){
      digitalWrite(e2[m], HIGH);
      mstate[m] = 4;
    }
    else if(mstate[m] ==6){
      digitalWrite(p1[m], LOW);
      digitalWrite(e1[m], LOW);
      mstate[m] = 5;
    }
    else if(mstate[m] ==7){
      digitalWrite(e1[m], HIGH);
      mstate[m] = 6;
    }
  }
  if(zdown){
    delay(slowDelay[m]);
  }else{
    delay(fastDelay[m]);
  }
}

///////////////////////////////////////////////////////////////////////////
// these functions are for limit switches only. I have not tested them
///////////////////////////////////////////////////////////////////////////
void goHome(){
  // just go in the -x and -y directions until you hit the limit switches
  while(!xlimit && !ylimit){
    oneStep(0, -1);
    oneStep(1, -1);
  }
  while(!xlimit){
    oneStep(0, -1);
  }
  while(!ylimit){
    oneStep(1, -1);
  }
  // back off the switches
  oneStep(0, 1);
  oneStep(1, 1);
  oneStep(0, 1);
  oneStep(1, 1);
}

void findCenter(){
  // travel over the full range then go to the center
  goHome();
  while(!xlimit && !ylimit){
    oneStep(0, 1);
    oneStep(1, 1);
  }
  while(!xlimit){
    oneStep(0, 1);
  }
  while(!ylimit){
    oneStep(1, 1);
  }

  int maxx = poss[0];
  int maxy = poss[1];
  while(poss[0] > maxx/2 && poss[1] > maxy/2){
    oneStep(0, -1);
    oneStep(1, -1);
  }
  while(poss[0] > maxx/2){
    oneStep(0, -1);
  }
  while(poss[1] > maxy/2){
    oneStep(1, -1);
  }
}


void hitXLimit(){
  if(digitalRead(xlimitPin) == HIGH){
    xlimit = true;
  }
  else{
    xlimit = false;
  }
}

void hitYLimit(){
  if(digitalRead(ylimitPin) == HIGH){
    ylimit = true;
  }
  else{
    ylimit = false;
  }
}
////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////
