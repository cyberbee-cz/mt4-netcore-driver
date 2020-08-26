//+------------------------------------------------------------------+
//|                                            NamedPipeExporter.mq4 |
//|                                         Copyright 2015, jimbulux |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2015, jimbulux"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#define COMM_CONNECTED "TERM:CONNECTED"
#define COMM_QUOTE "TERM:QUOTE:"
#define NEWLINE_CHAR "\n"

string PipeNamePrefix="\\\\.\\pipe\\";
int BufferSize = 256;

#define PIPE_ACCESS_INBOUND 1
#define PIPE_ACCESS_OUTBOUND 2
#define PIPE_ACCESS_DUPLEX 3

#define PIPE_TYPE_BYTE  0
#define PIPE_TYPE_MESSAGE  4
#define PIPE_READMODE_BYTE 0
#define PIPE_READMODE_MESSAGE 2

#define PIPE_WAIT 0
#define PIPE_NOWAIT 1

#define GenericRead  0x80000000
#define GenericWrite  0x40000000
#define OPEN_EXISTING  3

extern string PipeName="MetaTrader";

int INVALID_HANDLE_VALUE = 0xffffffff;
int PipeHandle = INVALID_HANDLE_VALUE;
int Buffer[64];  // 4 bytes/int * 64 = 256

#import "kernel32.dll"
int CreateNamedPipeA(string pipeName, int openMode, int pipeMode, 
   int maxInstances, int outBufferSize, int inBufferSize, 
   int defaultTimeOut, int security );
int WaitNamedPipeA( string lpNamedPipeName, int nTimeOut );
bool PeekNamedPipe( int pipeHandle, int& buffer[], int bufferSize, int& bytesRead[],
   int& totalBytesAvail[], int& bytesLeftThisMessage[] );
int CreateFileA( string name, int desiredAccess, int SharedMode,
   int security, int creation, int flags, int templateFile );
int WriteFile( int fileHandle, int& buffer[], int bytes, int& numOfBytes[], 
   int overlapped );
int ReadFile( int fileHandle, int& buffer[], int bytes, int& numOfBytes[], int overlapped );
int CloseHandle( int fileHandle );
int GetError();
#import

bool IsConnected = false;
string FullPipeName;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- create timer
   EventSetTimer(5);
   PipeHandle = INVALID_HANDLE_VALUE;
   bool bfirst=true;
   // Opening named pipe server connection
   while(!IsStopped())
   {
      OpenPipe("My.Pipe.Server");
      Sleep(250);
   }
   if(IsStopped()) {
      IsConnected = false;
      return(INIT_FAILED);
   }
   IsConnected = true;
   
      
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- destroy timer
   EventKillTimer();
      
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
//---
   string msg = ReadFromPipe();
   
   WriteIntoPipe("Test");
  }
//+------------------------------------------------------------------+

void OpenPipe(string pipeName) {
   FullPipeName = PipeNamePrefix + pipeName;

   if ( PipeHandle == INVALID_HANDLE_VALUE ) {
      if ( WaitNamedPipeA( FullPipeName, 1 ) == 0 ) {
         Print( "No pipe available" );
         return;
      }
      
      PipeHandle = CreateFileA( FullPipeName, GenericRead|GenericWrite, 
         0, 0,  OPEN_EXISTING, 0, 0 );
      Print( Symbol(), ": PipeHandle=", PipeHandle );
      if ( PipeHandle == INVALID_HANDLE_VALUE ){
         Print( "Pipe open failed" );
         return;
      } 
   }
}

string ReadFromPipe()
{
   int bytesRead[256];
   ReadFile(PipeHandle, Buffer, BufferSize, bytesRead, 0 );
   string message = StringFromBuffer(bytesRead[0]);
   
   return message;
}

void WriteIntoPipe(string message) {
   int numOfBytes[256];
   CopyToBuffer(message);
   int result = WriteFile( PipeHandle, Buffer, BufferSize, numOfBytes, 0);
}

string StringFromBuffer(int length) {
   string message = "";
   for ( int i = 0; i < length; i++ ) {
      int c = Buffer[i / 4];
      int off = i % 4;
      int shift = 0;
      if ( off == 1 )
         shift = 8;
      else if ( off == 2 )
         shift = 16;
      else if ( off == 3 )
         shift = 24;
      c = (c >> shift) & 0xff;
      message = message + CharToStr( c );
   }
   
   return( message );
}

void CopyToBuffer( string message ) {
   for ( int i = 0; i < 64; i++ )
      Buffer[i] = 0;
   
   for (int i = 0; i < StringLen( message ); i++ ) {
      int off = i % 4;
      int shift = 0;
      if ( off == 1 )
         shift = 8;
      else if ( off == 2 )
         shift = 16;
      else if ( off == 3 )
         shift = 24;
      Buffer[i/4] |= StringGetChar( message, i ) << shift;
   }
}