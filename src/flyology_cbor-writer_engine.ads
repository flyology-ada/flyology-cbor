with Ada.Streams;
with Flyology_CBOR.Destinations;
with Flyology_CBOR.Errors;
with Flyology_CBOR.Profiles;
with Flyology_CBOR.Values;
with Interfaces;

private generic
   type Destination_Type (<>) is limited private;

   with procedure Destination_Begin
     (Target : in out Destination_Type;
      Status : out Destinations.Begin_Status);

   with procedure Destination_Write
     (Target  : in out Destination_Type;
      Data    : Ada.Streams.Stream_Element_Array;
      Written : out Ada.Streams.Stream_Element_Count;
      Status  : out Destinations.Write_Status);

   with procedure Destination_Commit
     (Target : in out Destination_Type;
      Status : out Destinations.Commit_Status);

   with procedure Destination_Abort
     (Target : in out Destination_Type;
      Status : out Destinations.Abort_Status);

package Flyology_CBOR.Writer_Engine is
   type Writer_State is
     (Uninitialized,
      Ready,
      Active,
      Completed,
      Failed,
      Aborted);

   type Writer (Maximum_Syntax_Depth : Natural) is limited private;

   procedure Initialize
     (Self       : in out Writer;
      Profile    : Profiles.Writer_Profile;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Document
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Unsigned
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Negative_Argument
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Argument   : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Signed
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Interfaces.Integer_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_False
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic);

   procedure Put_True
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic);

   procedure Put_Null
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic);

   procedure Put_Undefined
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic);

   procedure Put_Simple
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Values.Simple_Code;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Float
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Values.Float_Value;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Byte_String
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Indefinite_Byte_String
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic);

   procedure Begin_Byte_String_Chunk
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Byte_String_Fragment
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Byte_String_Chunk
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic);

   procedure End_Byte_String
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic);

   procedure Begin_Text_String
     (Self         : in out Writer;
      Target       : in out Destination_Type;
      Octet_Length : Interfaces.Unsigned_64;
      Diagnostic   : out Errors.Diagnostic);

   procedure Begin_Indefinite_Text_String
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic);

   procedure Begin_Text_String_Chunk
     (Self         : in out Writer;
      Target       : in out Destination_Type;
      Octet_Length : Interfaces.Unsigned_64;
      Diagnostic   : out Errors.Diagnostic);

   procedure Put_Text_String_Fragment
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Text_String_Chunk
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic);

   procedure End_Text_String
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic);

   procedure Begin_Array
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Indefinite_Array
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic);

   procedure End_Array
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic);

   procedure Begin_Map
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Pair_Count : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Indefinite_Map
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic);

   procedure End_Map
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic);

   procedure Begin_Tag
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Number     : Values.Tag_Number;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Tag
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic);

   procedure Finish_Document
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic);

   procedure Abort_Document
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic);

   procedure Reset
     (Self       : in out Writer;
      Profile    : Profiles.Writer_Profile;
      Diagnostic : out Errors.Diagnostic);

   function State (Self : Writer) return Writer_State;
   function Has_Applied_Profile (Self : Writer) return Boolean;
   function Applied_Profile (Self : Writer) return Profiles.Writer_Profile;
   function Terminal_Diagnostic (Self : Writer) return Errors.Diagnostic;
   function Staged_Length (Self : Writer) return Interfaces.Unsigned_64;

private
   type Frame_Kind is
     (Array_Frame,
      Map_Frame,
      Tag_Frame,
      Indefinite_Byte_String_Frame,
      Indefinite_Text_String_Frame);

   type Syntax_Frame is record
      Kind          : Frame_Kind := Array_Frame;
      Indefinite    : Boolean := False;
      Remaining     : Interfaces.Unsigned_64 := 0;
      Expecting_Key : Boolean := True;
      Child_Done    : Boolean := False;
   end record;

   type Frame_Array is array (Natural range <>) of Syntax_Frame;

   type String_Mode is
     (No_String,
      Definite_Byte_String,
      Definite_Text_String,
      Byte_String_Chunk,
      Text_String_Chunk);

   type Writer (Maximum_Syntax_Depth : Natural) is limited record
      Current_State       : Writer_State := Uninitialized;
      Profile_Applied     : Boolean := False;
      Profile_Value       : Profiles.Writer_Profile;
      Last_Diagnostic     : Errors.Diagnostic;
      Staged              : Interfaces.Unsigned_64 := 0;
      Call_Ordinal        : Interfaces.Unsigned_64 := 0;
      Root_Started        : Boolean := False;
      Root_Complete       : Boolean := False;
      Depth               : Natural := 0;
      Stack               : Frame_Array (1 .. Maximum_Syntax_Depth);
      Active_String       : String_Mode := No_String;
      String_Remaining    : Interfaces.Unsigned_64 := 0;
      String_Written      : Interfaces.Unsigned_64 := 0;
      UTF8_Lead           : Ada.Streams.Stream_Element := 0;
      UTF8_Lead_Offset    : Interfaces.Unsigned_64 := 0;
      UTF8_Have           : Natural range 0 .. 4 := 0;
      UTF8_Need           : Natural range 0 .. 4 := 0;
      Destination_Call_Active : Boolean := False;
   end record;
end Flyology_CBOR.Writer_Engine;
