/**
 *  
 *  Version 2 - works with Processing 2.1.1
 *            - added support for translation commands 
 *            - added support for "rect" shapes (no other basic shapes are implemented
 *               yet, but they don't seem to be used by Inkscape or Gimp.)
 *  
 *  Update: 2014-3-28 - fixed translation bug, added drill point capability
 *  Update: 2014-4-1  - added cut depth and parameter adjustment
 *
 *  Reads an SVG image file, converts the path data into 
 *  a list of coordinates, then sends the coordinates
 *  over the serial connection to an arduino.
 *  NOTE: The arduino must have a compatible program. 
 *  (see sendData() method below)
 *  
 *  ALSO: This does not yet support quadratic Bezier curves(Q,q,T,t commands)
 *  but I've never seen those in Inkscape or Gimp files
 *  Does not yet support "transform" commands, though it would be
 *  oh so simple to add this.
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
import processing.serial.*;

//////////////////////////////////////////////
// Set these variables directly before running
//////////////////////////////////////////////
final String serialPort = "COM7"; // the name of the USB port
final String filePath = "C:/Users/Bilbo/Desktop/svgstuff/dialboard.svg"; // the SVG file path
final double precision = .1; // precision for interpolating curves (smaller = finer)
final double drillThreshold = .5; // paths with less than 5 nodes and size smaller than this are drills
final double maxdim = 55.6; // maximum dimension in mm (either height or width)
final boolean rotated = false; // true rotates 90 degrees: (maxy-y)->x, x->y
final boolean sendIt = true; // true=sends the data, false=just draws to screen
//////////////////////////////////////////////
// these are parameters that may be set on the arduino if desired
//////////////////////////////////////////////
boolean setArduinoParameters = true;
int sxdelay = 30;
int sydelay = 180;
int szdelay = 45;
int fxdelay = 3;
int fydelay = 18;
int fzdelay = 25;
double xstepsize = 56.889;
double ystepsize = 9.467;
int zlift = 200; // don't change this one just yet
int drillDepth = 400;
//////////////////////////////////////////////

ArrayList<Point> allpoints;
ArrayList<Point> drillpoints;
ArrayList<Integer> zchanges;
boolean zdown;
Serial sPort; 

void setup() {
  size(600, 600);
  allpoints = new ArrayList<Point>();
  drillpoints = new ArrayList<Point>();
  zchanges = new ArrayList<Integer>();
  zdown = false;
  // read the data file
  readData(filePath);
  if (allpoints.size()==0) {
    println("There was an error in the data file");
    return;
  }
  if(sendIt){
    sPort = new Serial(this, serialPort, 9600);
    if(sPort==null){
      println("couldn't find serial port");
    }else{
      // delay in case the arduino reset 
      delay(1000);
      
    }
  }
  
}

void draw() {
  // write it serially to the usb port to be read by the arduino
  if(sendIt && (sPort != null)){
    sendData();
  }
  // draw a picture of what it should look like on the screen
  makePicture();
  
  noLoop(); // only do it once
}

// reads the file
void readData(String fileName) {
  
  allpoints = new ArrayList<Point>();
  zchanges = new ArrayList<Integer>();
  
  int ind = -1;
  int indr = -1;
  boolean isRect = false;
  boolean hasTrans = false;
  int transLine = 0;
  boolean foundPath = false;
  boolean foundPData = false;
  String pstring = null; // holds the full path data in a string
  String[] pdata = null; // each element of the path data
  Point relpt = new Point(0.0, 0.0); // for relative commands
  Point startpt = new Point(0.0, 0.0); // for z commands
  
  // read all lines into an array
  String lines[] = loadStrings(fileName);
  if(lines == null){
    println("error reading file");
    return;
  }
  
  // wrap everything in a huge try block. Yes, I know this is not ideal.
  try{
    // search lines one by one to pick out path data
    for(int lind=0; lind<lines.length; lind++){
      // search for the beginning of a path: "<path" or a rect: "<rect"
      if(!foundPath){
        ind = lines[lind].indexOf("<path");
        indr = lines[lind].indexOf("<rect");
        // one of these should always be <0
        if(ind >= 0){
          isRect = false;
          foundPath = true;
          hasTrans = false;
        }else if(indr >= 0){
          isRect = true;
          foundPath = true;
          hasTrans = false;
        }else{
          continue;
        }
      }
      
      // if we got here, we found either a path or rect
      if(isRect){
        //we found a rect. This only has 4 important numbers
        //search lines until they are all found
        int remainingPars = 4;
        double rectx = 0.0;
        double recty = 0.0;
        double rectwidth = 0.0;
        double rectheight = 0.0;
        while(remainingPars > 0){
          //keep an eye out for transforms
          if(lines[lind].indexOf("transform=\"translate(") >= 0){
            hasTrans = true;
            transLine = lind;
          }
          
          if(lines[lind].indexOf("width=\"") >= 0){
            pstring = lines[lind].substring(lines[lind].indexOf("width=\"") + 7);
            pstring = pstring.substring(0, pstring.indexOf("\""));
            pdata = splitTokens(pstring, ", \t");
            rectwidth = Double.valueOf(pdata[0]).doubleValue();
            remainingPars--;
          }
          if(lines[lind].indexOf("height=\"") >= 0){
            pstring = lines[lind].substring(lines[lind].indexOf("height=\"") + 8);
            pstring = pstring.substring(0, pstring.indexOf("\""));
            pdata = splitTokens(pstring, ", \t");
            rectheight = Double.valueOf(pdata[0]).doubleValue();
            remainingPars--;
          }
          if(lines[lind].indexOf("x=\"") >= 0){
            pstring = lines[lind].substring(lines[lind].indexOf("x=\"") + 3);
            pstring = pstring.substring(0, pstring.indexOf("\""));
            pdata = splitTokens(pstring, ", \t");
            rectx = Double.valueOf(pdata[0]).doubleValue();
            remainingPars--;
          }
          if(lines[lind].indexOf("y=\"") >= 0){
            pstring = lines[lind].substring(lines[lind].indexOf("y=\"") + 3);
            pstring = pstring.substring(0, pstring.indexOf("\""));
            pdata = splitTokens(pstring, ", \t");
            recty = Double.valueOf(pdata[0]).doubleValue();
            remainingPars--;
          }
          if(remainingPars > 0){
            lind++;
          }
        }
        // now all rect parameters are found. build a path
        ArrayList<Point> pathpoints = new ArrayList<Point>();
        // lift and lower the pen
        zchanges.add(allpoints.size()+pathpoints.size());
        zchanges.add(-allpoints.size()-pathpoints.size()-1);
        // the start point is the upper left (x,y)
        pathpoints.add(new Point(rectx, recty));
        // lets go clockwise
        pathpoints.add(new Point(rectx+rectwidth, recty));
        pathpoints.add(new Point(rectx+rectwidth, recty+rectheight));
        pathpoints.add(new Point(rectx, recty+rectheight));
        pathpoints.add(new Point(rectx, recty));
        
        // here we have completed this rect. Yay!
        // read lines till we reach the true end of rect "/>"
        while(lines[lind].indexOf("/>") < 0){
          // there could still be a transform in there!
          if(lines[lind].indexOf("transform=\"translate(") >= 0){
            hasTrans = true;
            transLine = lind;
          }
          lind++;
        }
        if(lines[lind].indexOf("transform=\"translate(") >= 0){
          hasTrans = true;
          transLine = lind;
        }
        
        // if there was a transform, apply it to the path
        if(hasTrans){
          // translate all points by this much
          pstring = lines[lind].substring(lines[lind].indexOf("translate(") + 10);
          pstring = pstring.substring(0, pstring.indexOf(")"));
          pdata = splitTokens(pstring, ", \t");
          double transx = Double.valueOf(pdata[0]).doubleValue();
          double transy = 0.0;
          Point tmppoint;
          if(pdata.length > 1){
            transy = Double.valueOf(pdata[1]).doubleValue();
          }
          for(int arrayind=0; arrayind<pathpoints.size(); arrayind++){
            tmppoint = pathpoints.get(arrayind);
            pathpoints.set(arrayind, new Point(tmppoint.x+transx, tmppoint.y+transy));
          }
        }
        
        allpoints.addAll(pathpoints);
        foundPath = false;
        println("subpath complete, points: "+String.valueOf(pathpoints.size()));
        
      }else{
        // we found a path. Now search for the path data
        // NOTE: this will typically work for Inkscape and Gimp. 
        // Not guaranteed to work for all SVG editors
        if(!foundPData){
          ind = lines[lind].indexOf("d=\"M ");
          if(ind < 0){
            ind = lines[lind].indexOf("d=\"m ");
            if(ind < 0){
              continue;
            }else{
              foundPData = true;
              ind = lines[lind].indexOf('m');
            }
          }else{
            foundPData = true;
            ind = lines[lind].indexOf('M');
          }
        }
        // now we are on the first line of path data
        // let's read in the whole path data into one long string bastard
        //keep an eye out for transforms
        if(lines[lind].indexOf("transform=\"translate(") >= 0){
          hasTrans = true;
          transLine = lind;
        }
        pstring = lines[lind].substring(ind);
        if(pstring.indexOf("\"") >= 0){
          foundPData = false;
          pstring = pstring.substring(0, pstring.indexOf("\""));
        }
        while(foundPData){
          lind++;
          pstring = pstring + lines[lind];
          if(pstring.indexOf("\"") >= 0){
            foundPData = false;
            pstring = pstring.substring(0, pstring.indexOf("\""));
          }
          //keep an eye out for transforms
          if(lines[lind].indexOf("transform=\"translate(") >= 0){
            hasTrans = true;
            transLine = lind;
          }
        }
        // now split the string into parts
        pdata = splitTokens(pstring, ", \t");
        
        // now the task of parsing and interpolating
        int mode = -1; // 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15 = M,m,L,l,H,h,V,v,C,c,S,s,A,a,Z,z
        Point cntrlpt = null; // special point for s commands
        ArrayList<Point> pathpoints = new ArrayList<Point>();
        for(int i=0; i<pdata.length; i++){
          if(mode == 0){ mode = 2; }  // only one M/m command at a time
          if(mode == 1){ mode = 3; }
          if(pdata[i].charAt(0) == 'M'){
            mode = 0;
            i++;
          }else if(pdata[i].charAt(0) == 'm'){
            mode = 1;
            i++;
          }else if(pdata[i].charAt(0) == 'L'){
            mode = 2;
            i++;
          }else if(pdata[i].charAt(0) == 'l'){
            mode = 3;
            i++;
          }else if(pdata[i].charAt(0) == 'H'){
            mode = 4;
            i++;
          }else if(pdata[i].charAt(0) == 'h'){
            mode = 5;
            i++;
          }else if(pdata[i].charAt(0) == 'V'){
            mode = 6;
            i++;
          }else if(pdata[i].charAt(0) == 'v'){
            mode = 7;
            i++;
          }else if(pdata[i].charAt(0) == 'C'){
            mode = 8;
            i++;
          }else if(pdata[i].charAt(0) == 'c'){
            mode = 9;
            i++;
          }else if(pdata[i].charAt(0) == 'S'){
            if(mode < 8 || mode > 11){
              cntrlpt = relpt;
            }
            mode = 10;
            i++;
          }else if(pdata[i].charAt(0) == 's'){
            if(mode < 8 || mode > 11){
              cntrlpt = relpt;
            }
            mode = 11;
            i++;
          }else if(pdata[i].charAt(0) == 'A'){
            mode = 12;
            i++;
          }else if(pdata[i].charAt(0) == 'a'){
            mode = 13;
            i++;
          }else if(pdata[i].charAt(0) == 'Z'){
            mode = 14;
            //i++; don't need this
          }else if(pdata[i].charAt(0) == 'z'){
            mode = 15;
            //i++; don't need this
          }else if(pdata[i].charAt(0) == 'Q' || pdata[i].charAt(0) == 'q' || pdata[i].charAt(0) == 'T' || pdata[i].charAt(0) == 't'){
            println("Q,q,T,t not supported");
            return;
          }else{
            // repeated commands do not need repeated letters
          }
          
          if(mode == 0){
            // lift and lower the pen
            zchanges.add(allpoints.size()+pathpoints.size());
            zchanges.add(-allpoints.size()-pathpoints.size()-1);
            // this is followed by 2 numbers
            double tmpx = Double.valueOf(pdata[i]).doubleValue();
            double tmpy = Double.valueOf(pdata[i+1]).doubleValue();
            relpt = new Point(tmpx, tmpy);
            startpt = new Point(tmpx, tmpy);
            pathpoints.add(new Point(tmpx, tmpy));
            i++;
          }else if(mode == 1){
            // lift and lower the pen
            zchanges.add(allpoints.size()+pathpoints.size());
            zchanges.add(-allpoints.size()-pathpoints.size()-1);
            double x = 0.0;
            double y = 0.0;
            if(pathpoints.size() > 0){
              x = relpt.x;
              y = relpt.y;
            }
            // this is followed by 2 numbers
            double tmpx = x + Double.valueOf(pdata[i]).doubleValue();
            double tmpy = y + Double.valueOf(pdata[i+1]).doubleValue();
            relpt = new Point(tmpx, tmpy);
            startpt = new Point(tmpx, tmpy);
            pathpoints.add(new Point(tmpx, tmpy));
            i++;
          }else if(mode == 2){
            // this is followed by 2 numbers
            double tmpx = Double.valueOf(pdata[i]).doubleValue();
            double tmpy = Double.valueOf(pdata[i+1]).doubleValue();
            relpt = new Point(tmpx, tmpy);
            pathpoints.add(new Point(tmpx, tmpy));
            i++;
          }else if(mode == 3){
            // this is followed by 2 numbers
            double tmpx = relpt.x + Double.valueOf(pdata[i]).doubleValue();
            double tmpy = relpt.y + Double.valueOf(pdata[i+1]).doubleValue();
            relpt = new Point(tmpx, tmpy);
            pathpoints.add(new Point(tmpx, tmpy));
            i++;
          }else if(mode == 4){
            // this is followed by 1 number
            pathpoints.add(new Point(Double.valueOf(pdata[i]).doubleValue(), relpt.y));
            relpt = new Point(Double.valueOf(pdata[i]).doubleValue(), relpt.y);
          }else if(mode == 5){
            // this is followed by 1 number
            double tmpx = relpt.x + Double.valueOf(pdata[i]).doubleValue();
            pathpoints.add(new Point(tmpx, relpt.y));
            relpt = new Point(tmpx, relpt.y);
          }else if(mode == 6){
            // this is followed by 1 number
            pathpoints.add(new Point(relpt.x, Double.valueOf(pdata[i]).doubleValue()));
            relpt = new Point(relpt.x, Double.valueOf(pdata[i]).doubleValue());
          }else if(mode == 7){
            // this is followed by 1 number
            double tmpy = relpt.y + Double.valueOf(pdata[i]).doubleValue();
            pathpoints.add(new Point(relpt.x, tmpy));
            relpt = new Point(relpt.x, tmpy);
          }else if(mode == 8){
            // this is followed by 6 numbers
            double x = relpt.x;
            double y = relpt.y;
            double xc1 = Double.valueOf(pdata[i]).doubleValue();
            double yc1 = Double.valueOf(pdata[i+1]).doubleValue();
            double xc2 = Double.valueOf(pdata[i+2]).doubleValue();
            double yc2 = Double.valueOf(pdata[i+3]).doubleValue();
            double px = Double.valueOf(pdata[i+4]).doubleValue();
            double py = Double.valueOf(pdata[i+5]).doubleValue();
            cntrlpt = new Point(x + x-xc2, y + y-yc2);
            pathpoints.addAll(interpolateCurve(relpt, new Point(xc1, yc1), new Point(xc2, yc2), new Point(px, py)));
            relpt = new Point(px, py);
            i += 5;
          }else if(mode == 9){
            // this is followed by 6 numbers
            double x = relpt.x;
            double y = relpt.y;
            double xc1 = x + Double.valueOf(pdata[i]).doubleValue();
            double yc1 = y + Double.valueOf(pdata[i+1]).doubleValue();
            double xc2 = x + Double.valueOf(pdata[i+2]).doubleValue();
            double yc2 = y + Double.valueOf(pdata[i+3]).doubleValue();
            double px = x + Double.valueOf(pdata[i+4]).doubleValue();
            double py = y + Double.valueOf(pdata[i+5]).doubleValue();
            cntrlpt = new Point(x + x-xc2, y + y-yc2);
            pathpoints.addAll(interpolateCurve(relpt, new Point(xc1, yc1), new Point(xc2, yc2), new Point(px, py)));
            relpt = new Point(px, py);
            i += 5;
          }else if(mode == 10){
            // this is followed by 4 numbers
            double x = relpt.x;
            double y = relpt.y;
            double xc2 = Double.valueOf(pdata[i]).doubleValue();
            double yc2 = Double.valueOf(pdata[i+1]).doubleValue();
            double px = Double.valueOf(pdata[i+2]).doubleValue();
            double py = Double.valueOf(pdata[i+3]).doubleValue();
            pathpoints.addAll(interpolateCurve(relpt, cntrlpt, new Point(xc2, yc2), new Point(px, py)));
            relpt = new Point(px, py);
            i += 3;
            cntrlpt = new Point(x + x-xc2, y + y-yc2);
          }else if(mode == 11){
            // this is followed by 4 numbers
            double x = relpt.x;
            double y = relpt.y;
            double xc2 = x + Double.valueOf(pdata[i]).doubleValue();
            double yc2 = y + Double.valueOf(pdata[i+1]).doubleValue();
            double px = x + Double.valueOf(pdata[i+2]).doubleValue();
            double py = y + Double.valueOf(pdata[i+3]).doubleValue();
            pathpoints.addAll(interpolateCurve(relpt, cntrlpt, new Point(xc2, yc2), new Point(px, py)));
            relpt = new Point(px, py);
            i += 3;
            cntrlpt = new Point(x + x-xc2, y + y-yc2);
          }else if(mode == 12){
            // this is followed by 7 numbers
            double rx = Double.valueOf(pdata[i]).doubleValue();
            double ry = Double.valueOf(pdata[i+1]).doubleValue();
            double xrot = Double.valueOf(pdata[i+2]).doubleValue();
            boolean bigarc = Integer.valueOf(pdata[i+3]) > 0;
            boolean sweep = Integer.valueOf(pdata[i+4]) > 0;
            double px = Double.valueOf(pdata[i+5]).doubleValue();
            double py = Double.valueOf(pdata[i+6]).doubleValue();
            pathpoints.addAll(interpolateArc(relpt, rx, ry, xrot, bigarc, sweep, new Point(px, py)));
            relpt = new Point(px, py);
            i += 6;
          }else if(mode == 13){
            // this is followed by 7 numbers
            double x = relpt.x;
            double y = relpt.y;
            double rx = Double.valueOf(pdata[i]).doubleValue();
            double ry = Double.valueOf(pdata[i+1]).doubleValue();
            double xrot = Double.valueOf(pdata[i+2]).doubleValue();
            boolean bigarc = Integer.valueOf(pdata[i+3]) > 0;
            boolean sweep = Integer.valueOf(pdata[i+4]) > 0;
            double px = x + Double.valueOf(pdata[i+5]).doubleValue();
            double py = y + Double.valueOf(pdata[i+6]).doubleValue();
            pathpoints.addAll(interpolateArc(relpt, rx, ry, xrot, bigarc, sweep, new Point(px, py)));
            relpt = new Point(px, py);
            i += 6;
          }else if(mode == 14){
            double tmpx = startpt.x;
            double tmpy = startpt.y;
            pathpoints.add(new Point(tmpx, tmpy));
            relpt = new Point(tmpx, tmpy);
          }else if(mode == 15){
            double tmpx = startpt.x;
            double tmpy = startpt.y;
            pathpoints.add(new Point(tmpx, tmpy));
            relpt = new Point(tmpx, tmpy);
          }
        } // end pdata loop
        
        // here we have completed this path. Yay!
        // read lines till we reach the true end of path "/>"
        while(lines[lind].indexOf("/>") < 0){
          // there could still be a transform in there!
          if(lines[lind].indexOf("transform=\"translate(") >= 0){
            hasTrans = true;
            transLine = lind;
          }
          lind++;
        }
        if(lines[lind].indexOf("transform=\"translate(") >= 0){
          hasTrans = true;
          transLine = lind;
        }
        
        // if there was a transform, apply it to the path
        if(hasTrans){
          // translate all points by this much
          pstring = lines[lind].substring(lines[lind].indexOf("translate(") + 10);
          pstring = pstring.substring(0, pstring.indexOf(")"));
          pdata = splitTokens(pstring, ", \t");
          double transx = Double.valueOf(pdata[0]).doubleValue();
          double transy = 0.0;
          Point tmppoint;
          if(pdata.length > 1){
            transy = Double.valueOf(pdata[1]).doubleValue();
          }
          for(int arrayind=0; arrayind<pathpoints.size(); arrayind++){
            tmppoint = pathpoints.get(arrayind);
            pathpoints.set(arrayind, new Point(tmppoint.x+transx, tmppoint.y+transy));
          }
        }
        
        // if the path has 4 or fewer nodes and size less than drillthreshold, set drill point
        boolean isdrill = false;
        if(pathpoints.size() < 5){
          double minx = 1e10;
          double miny = 1e10;
          double maxx = -1e10;
          double maxy = -1e10;
          double x, y;
          for (int i=0; i<pathpoints.size(); i++) {
            x = pathpoints.get(i).x;
            y = pathpoints.get(i).y;
            if(x > maxx){ maxx = x; }
            if(x < minx){ minx = x; }
            if(y > maxy){ maxy = y; }
            if(y < miny){ miny = y; }
          }
          if((maxx - minx < drillThreshold) && (maxy - miny < drillThreshold)){
            isdrill = true;
          }
        }
        if(isdrill){
          drillpoints.add(pathpoints.get(1));
          println("drill point complete");
        }else{
          allpoints.addAll(pathpoints);
          println("subpath complete, points: "+String.valueOf(pathpoints.size()));
        }
        
        foundPath = false;
        
      } // end "<path" parsing
        
    } // end line searching
    
  } // end try block
  catch(Exception e) {
    e.printStackTrace();
  }
  
  // if needed, rotate all points and drills
  if(rotated){
    double tmp;
    double maxy = 0;
    for (int i=0; i<allpoints.size(); i++) {
      tmp = allpoints.get(i).y;
      if(tmp > maxy){
        maxy = tmp;
      }
    }
    for (int i=0; i<allpoints.size(); i++) {
      tmp = allpoints.get(i).x;
      allpoints.get(i).x = maxy - allpoints.get(i).y;
      allpoints.get(i).y = tmp;
    }
    for (int i=0; i<drillpoints.size(); i++) {
      tmp = drillpoints.get(i).x;
      drillpoints.get(i).x = maxy - drillpoints.get(i).y;
      drillpoints.get(i).y = tmp;
    }
  }
  
  // now all lines in the file have been processed
  
  println("total path points:"+allpoints.size());
  println("total drill points:"+drillpoints.size());
}

/*
* Interpolate the cubic Bezier curves (commands C,c,S,s)
*/
ArrayList<Point> interpolateCurve(Point p1, Point pc1, Point pc2, Point p2) {

  ArrayList<Point> pts = new ArrayList<Point>();

  pts.add(0, p1);
  pts.add(1, p2);
  double maxdist = Math.sqrt((p1.x-p2.x)*(p1.x-p2.x) + (p1.y-p2.y)*(p1.y-p2.y));
  double interval = 1.0;
  double win = 0.0;
  double iin = 1.0;
  int segments = 1;
  double tmpx, tmpy;

  while (maxdist > precision && segments < 1000) {
    interval = interval/2.0;
    segments = segments*2;

    for (int i=1; i<segments; i+=2) {
      win = 1-interval*i;
      iin = interval*i;
      tmpx = win*win*win*p1.x + 3*win*win*iin*pc1.x + 3*win*iin*iin*pc2.x + iin*iin*iin*p2.x;
      tmpy = win*win*win*p1.y + 3*win*win*iin*pc1.y + 3*win*iin*iin*pc2.y + iin*iin*iin*p2.y;
      pts.add(i, new Point(tmpx, tmpy));
    }
    if(segments > 3){
      maxdist = 0.0;
      for (int i=0; i<pts.size()-2; i++) {
        // this is the deviation from a straight line between 3 points
        tmpx = (pts.get(i).x-pts.get(i+1).x)*(pts.get(i).x-pts.get(i+1).x) + (pts.get(i).y-pts.get(i+1).y)*(pts.get(i).y-pts.get(i+1).y) - ((pts.get(i).x-pts.get(i+2).x)*(pts.get(i).x-pts.get(i+2).x) + (pts.get(i).y-pts.get(i+2).y)*(pts.get(i).y-pts.get(i+2).y))/4.0;
        if (tmpx > maxdist) {
          maxdist = tmpx;
        }
      }
      maxdist = Math.sqrt(maxdist);
    }
  }

  return pts;
}

/*
* Interpolate the elliptical arcs (commands A,a)
*/
ArrayList<Point> interpolateArc(Point p1, double rx, double ry, double xrot, boolean bigarc, boolean sweep, Point p2) {

  ArrayList<Point> pts = new ArrayList<Point>();

  pts.add(0, p1);
  pts.add(1, p2);
  // if the ellipse is too small to draw
  if(Math.abs(rx) <= precision || Math.abs(ry) <= precision){
    return pts;
  }
  
  // Now we begin the task of converting the stupid SVG arc format 
  // into something actually useful (method derived from SVG specification)
  
  // convert xrot to radians
  xrot = xrot*PI/180.0;
  
  // radius check
  double x1 = Math.cos(xrot)*(p1.x-p2.x)/2.0 + Math.sin(xrot)*(p1.y-p2.y)/2.0;
  double y1 = -Math.sin(xrot)*(p1.x-p2.x)/2.0 + Math.cos(xrot)*(p1.y-p2.y)/2.0;
  
  rx = Math.abs(rx);
  ry = Math.abs(ry);
  double rchk = x1*x1/rx/rx + y1*y1/ry/ry;
  if(rchk > 1.0){
    rx = Math.sqrt(rchk)*rx;
    ry = Math.sqrt(rchk)*ry;
  }
  
  // find the center
  double sq = (rx*rx*ry*ry - rx*rx*y1*y1 - ry*ry*x1*x1)/(rx*rx*y1*y1 + ry*ry*x1*x1);
  if(sq < 0){
    sq = 0;
  }
  sq = Math.sqrt(sq);
  double cx1 = 0.0;
  double cy1 = 0.0;
  if(bigarc==sweep){
    cx1 = -sq*rx*y1/ry;
    cy1 = sq*ry*x1/rx;
  }else{
    cx1 = sq*rx*y1/ry;
    cy1 = -sq*ry*x1/rx;
  }
  double cx = (p1.x+p2.x)/2.0 + Math.cos(xrot)*cx1 - Math.sin(xrot)*cy1;
  double cy = (p1.y+p2.y)/2.0 + Math.sin(xrot)*cx1 + Math.cos(xrot)*cy1;
  
  // find angle start and angle extent
  double theta = 0.0;
  double dtheta = 0.0;
  double ux = (x1-cx1)/rx;
  double uy = (y1-cy1)/ry;
  double vx = (-x1-cx1)/rx;
  double vy = (-y1-cy1)/ry;
  double thing = Math.sqrt(ux*ux + uy*uy);
  double thing2 = thing * Math.sqrt(vx*vx + vy*vy);
  if(thing == 0){
    thing = 1e-7;
  }
  if(thing2 == 0){
    thing2 = 1e-7;
  }
  if(uy < 0){
    theta = -Math.acos(ux/thing);
  }else{
    theta = Math.acos(ux/thing);
  }
  
  if(ux*vy-uy*vx < 0){
    dtheta = -Math.acos((ux*vx+uy*vy)/thing2);
  }else{
    dtheta = Math.acos((ux*vx+uy*vy)/thing2);
  }
  dtheta = dtheta%(2*PI);
  if(sweep && dtheta < 0){
    dtheta += 2*PI;
  }
  if(!sweep && dtheta > 0){
    dtheta -= 2*PI;
  }
  
  // Now we have converted from stupid SVG arcs to something useful.
  
  double maxdist = 100;
  double interval = dtheta;
  int segments = 1;
  double tmpx, tmpy;

  while (maxdist > precision && segments < 1000) {
    interval = interval/2.0;
    segments = segments*2;

    for (int i=1; i<=segments; i+=2) {
      tmpx = cx + rx*Math.cos(theta+interval*i)*Math.cos(xrot) - ry*Math.sin(theta+interval*i)*Math.sin(xrot);
      tmpy = cy + rx*Math.cos(theta+interval*i)*Math.sin(xrot) + ry*Math.sin(theta+interval*i)*Math.cos(xrot);
      pts.add(i, new Point(tmpx, tmpy));
    }

    if(segments > 3){
      maxdist = 0.0;
      for (int i=0; i<pts.size()-2; i++) {
        // this is the deviation from a straight line between 3 points
        tmpx = (pts.get(i).x-pts.get(i+1).x)*(pts.get(i).x-pts.get(i+1).x) + (pts.get(i).y-pts.get(i+1).y)*(pts.get(i).y-pts.get(i+1).y) - ((pts.get(i).x-pts.get(i+2).x)*(pts.get(i).x-pts.get(i+2).x) + (pts.get(i).y-pts.get(i+2).y)*(pts.get(i).y-pts.get(i+2).y))/4.0;
        if (tmpx > maxdist) {
          maxdist = tmpx;
        }
      }
      maxdist = Math.sqrt(maxdist);
    }
  }

  return pts;
}

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////

/*
* IMPORTANT: This is the way the data is sent
*  'S' signals the beginning of transmission
*  'A' signals a raise
*  'Z' signals a lower
*  'D' signals a drill point
*  numbers are sent multiplied by 10000 and truncated to int 
*  numbers are sent as strings, one character at a time
*  '.' signals the end of a number
*  'T' signals the end of the transmission
*/
void sendData() {
  // first of all, check the connection
  int timeLimit = 0;
  while (sPort.available () < 1) {
    sPort.write('#');
    delay(10);
    timeLimit++;
    if (timeLimit > 3000) {
      println("timed out");
      return;
    }
  }
  int check = sPort.read();
  if(check == '@'){
    println("Arduino connected");
  }else if(check == '!'){
    println("connected, but strange");
  }else{
    println("connected, but with error");
  }
  
  // wait for z axis calibration
  timeLimit = 0;
  boolean zcal = true;
  while(zcal){
    if(sPort.available()>0){
      if(sPort.read() == 'Z'){
        zcal = false;
      }
    }
    delay(10);
    timeLimit++;
    if (timeLimit > 30000) {
      println("timed out");
      return;
    }
  }
  
  // if desired, set parameters
  if(setArduinoParameters){
    // set the slow delay
    sPort.write('P');
    sPort.write('s');
    sendNumber(sxdelay*10000);
    sendNumber(sydelay*10000);
    sendNumber(szdelay*10000);
    // set the fast delay
    sPort.write('P');
    sPort.write('f');
    sendNumber(fxdelay*10000);
    sendNumber(fydelay*10000);
    sendNumber(fzdelay*10000);
    // set the x step size
    sPort.write('P');
    sPort.write('x');
    sendNumber((int)(xstepsize*10000));
    // set the y step size
    sPort.write('P');
    sPort.write('y');
    sendNumber((int)(ystepsize*10000));
    // set zlift
    sPort.write('P');
    sPort.write('z');
    sendNumber((int)(zlift*10000));
    // set drill depth
    sPort.write('P');
    sPort.write('d');
    sendNumber((int)(drillDepth*10000));
  }
  
  // first rescale and translate the data
  // find max and min data
  double minx = 1e10;
  double maxx = -1e10;
  double miny = 1e10;
  double maxy = -1e10;
  double x, y, scl;
  for (int i=0; i<allpoints.size(); i++) {
    x = allpoints.get(i).x;
    y = allpoints.get(i).y;
    if(x > maxx){ maxx = x; }
    if(x < minx){ minx = x; }
    if(y > maxy){ maxy = y; }
    if(y < miny){ miny = y; }
  }
  if(maxy-miny > maxx-minx){
    scl = maxdim/(maxy-miny);
  }else{
    scl = maxdim/(maxx-minx);
  }
  for (int i=0; i<allpoints.size(); i++) {
    allpoints.get(i).x = scl*(allpoints.get(i).x - minx);
    allpoints.get(i).y = scl*(allpoints.get(i).y - miny);
  }
  for (int i=0; i<drillpoints.size(); i++) {
    drillpoints.get(i).x = scl*(drillpoints.get(i).x - minx);
    drillpoints.get(i).y = scl*(drillpoints.get(i).y - miny);
  }
  
  // Then send the data 
  check = 0;
  String xdat, ydat;
  // clear the port
  while (sPort.available () > 0) {
    sPort.read();
  }
  // signal to begin 
  sPort.write('S');
  // send each point
  for(int i=0; i<allpoints.size(); i++){
    // if there is a z change, do that first
    for(int j=0; j<zchanges.size(); j++){
      if ((zchanges.get(j) == i || zchanges.get(j) == -i) && i > 0) {
        if (zchanges.get(j) == i) {
          sPort.write('A'); // this moves the pen up
        }
        else {
          sPort.write('Z'); // this moves the pen down
        }
        timeLimit = 0;
        while (sPort.available () < 1) {
          delay(10);
          timeLimit++;
          if (timeLimit > 60000) {
            println("timed out");
            return;
          }
        }
        check = sPort.read();
        zdown = !zdown;
        println("switched Z: "+zdown);
        break;
      }
    }
    // send a string of x data, wait for reply
    sendNumber((int)(allpoints.get(i).x*10000));
    
    // send a string of y data, wait for reply
    sendNumber((int)(allpoints.get(i).y*10000));

    println("sent N:"+i+" X:"+String.valueOf((int)(allpoints.get(i).x*10000))+" Y:"+String.valueOf((int)(allpoints.get(i).y*10000)));
  }
  // now send drill points
  for(int i=0; i<drillpoints.size(); i++){
    // if z is down, lift it before moving
    if(zdown){
      sPort.write('A'); // this moves z up
      timeLimit = 0;
      while (sPort.available () < 1) {
        delay(10);
        timeLimit++;
        if (timeLimit > 60000) {
          println("timed out");
          return;
        }
      }
      check = sPort.read();
      zdown = !zdown;
    }
    // send a string of x data, wait for reply
    sendNumber((int)(drillpoints.get(i).x*10000));
    
    // send a string of y data, wait for reply
    sendNumber((int)(drillpoints.get(i).y*10000));
    
    // send the drill command
    sPort.write('D'); // this drills
    timeLimit = 0;
    while (sPort.available () < 1) {
      delay(10);
      timeLimit++;
      if (timeLimit > 12000) {
        println("timed out");
        return;
      }
    }
    check = sPort.read();
    
    println("drilled:"+i+" X:"+String.valueOf(drillpoints.get(i).x)+" Y:"+String.valueOf(drillpoints.get(i).y));
  }
  
  // now we have sent all of the data. Yay!
  // signal to end 
  sPort.write('T');
  
  println("Sending complete");
}

void sendNumber(int num){
  String numstring = String.valueOf(num);
  for (int j=0; j<numstring.length(); j++) {
    sPort.write(numstring.charAt(j));
  }
  sPort.write('.');
  int timeLimit = 0;
  while (sPort.available () < 1) {
    delay(10);
    timeLimit++;
    if (timeLimit > 60000) {
      println("timed out");
      return;
    }
  }
  //char check = sPort.read();
  while (sPort.available () > 0) {
    sPort.read();
  }
}

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////

/*
* This draws a picture from the list of coordinates
*/
void makePicture() {
  int x0 = 50;
  int y0 = 50;
  int xn = 0;
  int yn = 0;
  float scl = 1.0; // pixels per mm
  float tmpx = 0.0;
  float tmpy = 0.0;
  int sign = 1;
  zdown = true;
  // find max and min data
  double minx = 1e10;
  double maxx = -1e10;
  double miny = 1e10;
  double maxy = -1e10;
  double x, y;
  for (int i=0; i<allpoints.size(); i++) {
    x = allpoints.get(i).x;
    y = allpoints.get(i).y;
    if(x > maxx){ maxx = x; }
    if(x < minx){ minx = x; }
    if(y > maxy){ maxy = y; }
    if(y < miny){ miny = y; }
  }
  if(maxy-miny > maxx-minx){
    scl = (float)(height*1.0/(maxy-miny));
  }else{
    scl = (float)(width*1.0/(maxx-minx));
  }
  
  x0 = (int)(minx*scl);
  y0 = (int)(miny*scl);
  
  for (int i=0; i<allpoints.size(); i++) {
    for (int j=0; j<zchanges.size(); j++) {
      if (zchanges.get(j) == i) {
        zdown = false;
      }
      if (zchanges.get(j) == -i && i > 0) {
        zdown = true;
      }
    }
    tmpx = (float)allpoints.get(i).x;
    tmpy = (float)allpoints.get(i).y;
    if (zdown) {
      line(xn-x0, (yn-y0), int(tmpx*scl)-x0, (int(tmpy*scl)-y0));
    }
    xn = int(tmpx*scl);
    yn = int(tmpy*scl);
  }
  for (int i=0; i<drillpoints.size(); i++) {
    tmpx = (float)drillpoints.get(i).x;
    tmpy = (float)drillpoints.get(i).y;
    ellipse(int(tmpx*scl)-x0, int(tmpy*scl)-y0, 10, 10);
  }
}

// a convenience class for storing 2-D double coordinates
class Point {
  public double x;
  public double y;
  Point(double nx, double ny) {
    x = nx;
    y = ny;
  }
}

