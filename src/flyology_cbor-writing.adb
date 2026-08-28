package body Flyology_CBOR.Writing is

   procedure Initialize
     (Self       : in out Writer;
      Profile    : Profiles.Writer_Profile;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Initialize (Self.Core, Profile, Diagnostic);
   end Initialize;

   procedure Begin_Document
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Document (Self.Core, Target, Diagnostic);
   end Begin_Document;

   procedure Put_Unsigned
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Unsigned (Self.Core, Target, Value, Diagnostic);
   end Put_Unsigned;

   procedure Put_Negative_Argument
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Argument   : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Negative_Argument (Self.Core, Target, Argument, Diagnostic);
   end Put_Negative_Argument;

   procedure Put_Signed
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Interfaces.Integer_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Signed (Self.Core, Target, Value, Diagnostic);
   end Put_Signed;

   procedure Put_False
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_False (Self.Core, Target, Diagnostic);
   end Put_False;

   procedure Put_True
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_True (Self.Core, Target, Diagnostic);
   end Put_True;

   procedure Put_Null
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Null (Self.Core, Target, Diagnostic);
   end Put_Null;

   procedure Put_Undefined
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Undefined (Self.Core, Target, Diagnostic);
   end Put_Undefined;

   procedure Put_Simple
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Values.Simple_Code;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Simple (Self.Core, Target, Value, Diagnostic);
   end Put_Simple;

   procedure Put_Float
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Values.Float_Value;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Float (Self.Core, Target, Value, Diagnostic);
   end Put_Float;

   procedure Begin_Byte_String
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Byte_String (Self.Core, Target, Length, Diagnostic);
   end Begin_Byte_String;

   procedure Begin_Indefinite_Byte_String
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Indefinite_Byte_String (Self.Core, Target, Diagnostic);
   end Begin_Indefinite_Byte_String;

   procedure Begin_Byte_String_Chunk
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Byte_String_Chunk (Self.Core, Target, Length, Diagnostic);
   end Begin_Byte_String_Chunk;

   procedure Put_Byte_String_Fragment
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Byte_String_Fragment (Self.Core, Target, Value, Diagnostic);
   end Put_Byte_String_Fragment;

   procedure End_Byte_String_Chunk
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.End_Byte_String_Chunk (Self.Core, Target, Diagnostic);
   end End_Byte_String_Chunk;

   procedure End_Byte_String
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.End_Byte_String (Self.Core, Target, Diagnostic);
   end End_Byte_String;

   procedure Begin_Text_String
     (Self         : in out Writer;
      Target       : in out Destination_Type;
      Octet_Length : Interfaces.Unsigned_64;
      Diagnostic   : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Text_String (Self.Core, Target, Octet_Length, Diagnostic);
   end Begin_Text_String;

   procedure Begin_Indefinite_Text_String
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Indefinite_Text_String (Self.Core, Target, Diagnostic);
   end Begin_Indefinite_Text_String;

   procedure Begin_Text_String_Chunk
     (Self         : in out Writer;
      Target       : in out Destination_Type;
      Octet_Length : Interfaces.Unsigned_64;
      Diagnostic   : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Text_String_Chunk (Self.Core, Target, Octet_Length, Diagnostic);
   end Begin_Text_String_Chunk;

   procedure Put_Text_String_Fragment
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Text_String_Fragment (Self.Core, Target, Value, Diagnostic);
   end Put_Text_String_Fragment;

   procedure End_Text_String_Chunk
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.End_Text_String_Chunk (Self.Core, Target, Diagnostic);
   end End_Text_String_Chunk;

   procedure End_Text_String
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.End_Text_String (Self.Core, Target, Diagnostic);
   end End_Text_String;

   procedure Begin_Array
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Array (Self.Core, Target, Length, Diagnostic);
   end Begin_Array;

   procedure Begin_Indefinite_Array
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Indefinite_Array (Self.Core, Target, Diagnostic);
   end Begin_Indefinite_Array;

   procedure End_Array
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.End_Array (Self.Core, Target, Diagnostic);
   end End_Array;

   procedure Begin_Map
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Pair_Count : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Map (Self.Core, Target, Pair_Count, Diagnostic);
   end Begin_Map;

   procedure Begin_Indefinite_Map
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Indefinite_Map (Self.Core, Target, Diagnostic);
   end Begin_Indefinite_Map;

   procedure End_Map
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.End_Map (Self.Core, Target, Diagnostic);
   end End_Map;

   procedure Begin_Tag
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Number     : Values.Tag_Number;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Tag (Self.Core, Target, Number, Diagnostic);
   end Begin_Tag;

   procedure End_Tag
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.End_Tag (Self.Core, Target, Diagnostic);
   end End_Tag;

   procedure Finish_Document
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Finish_Document (Self.Core, Target, Diagnostic);
   end Finish_Document;

   procedure Abort_Document
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Abort_Document (Self.Core, Target, Diagnostic);
   end Abort_Document;

   procedure Reset
     (Self       : in out Writer;
      Profile    : Profiles.Writer_Profile;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Reset (Self.Core, Profile, Diagnostic);
   end Reset;

   function State (Self : Writer) return Writer_State is
     (case Engine.State (Self.Core) is
         when Engine.Uninitialized => Uninitialized,
         when Engine.Ready         => Ready,
         when Engine.Active        => Active,
         when Engine.Completed     => Completed,
         when Engine.Failed        => Failed,
         when Engine.Aborted       => Aborted);

   function Has_Applied_Profile (Self : Writer) return Boolean is
     (Engine.Has_Applied_Profile (Self.Core));

   function Applied_Profile (Self : Writer) return Profiles.Writer_Profile is
     (Engine.Applied_Profile (Self.Core));

   function Terminal_Diagnostic (Self : Writer) return Errors.Diagnostic is
     (Engine.Terminal_Diagnostic (Self.Core));

end Flyology_CBOR.Writing;
