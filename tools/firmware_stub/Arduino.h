#pragma once
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#include <ctype.h>
struct __FlashStringHelper;
#define constrain(x, lo, hi) ((x) < (lo) ? (lo) : ((x) > (hi) ? (hi) : (x)))
#define HIGH 1
#define LOW 0
#define INPUT_PULLUP 2
#define INPUT 0
#define OUTPUT 1
#define A0 14
#define A4 18
#define A5 19
#define DEG_TO_RAD 0.0174532925f
#define F(x) (reinterpret_cast<const __FlashStringHelper *>(x))
#define max(a,b) ((a) > (b) ? (a) : (b))
typedef uint8_t byte;
unsigned long millis();
unsigned long micros();
void delay(unsigned long);
void delayMicroseconds(unsigned int);
void pinMode(int, int);
void digitalWrite(int, int);
int digitalRead(int);
int analogRead(int);
void noInterrupts();
void interrupts();
long random(long, long);
struct String {
  String(); String(const char*); String(int); String(char);
  const char* c_str() const;
  bool startsWith(const char*) const;
  String substring(int) const;
  long toInt() const;
  void trim();
  void toUpperCase();
  int length() const;
  bool operator==(const char*) const;
  String& operator+=(char);
  String& operator+=(const char*);
};
struct SerialC {
  void begin(long);
  int available();
  int read();
  String readStringUntil(char);
  void print(const __FlashStringHelper*);
  void print(const char*); void print(char); void print(float, int); void print(int); void print(unsigned long); void print(long);
  void println(const __FlashStringHelper*);
  void println(const char*); void println(char); void println(float, int); void println(int); void println(unsigned long); void println(long);
};
extern SerialC Serial;
