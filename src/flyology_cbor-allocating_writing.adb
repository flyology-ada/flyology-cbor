package body Flyology_CBOR.Allocating_Writing is

   use type Ada.Streams.Stream_Element_Count;
   use type Engine.Writer_State;

   procedure Destination_Begin
     (Target : in out Destination;
      Status : out Destinations.Begin_Status)
   is
   begin
      Target.Data.Clear;
      Target.Committed := 0;
      Target.Transaction_Open := True;
      Target.Storage_Failed := False;
      Status := Destinations.Begin_Succeeded;
   end Destination_Begin;

   procedure Destination_Write
     (Target  : in out Destination;
      Data    : Ada.Streams.Stream_Element_Array;
      Written : out Ada.Streams.Stream_Element_Count;
      Status  : out Destinations.Write_Status)
   is
      Original_Length : constant Ada.Streams.Stream_Element_Count :=
        Ada.Streams.Stream_Element_Count (Target.Data.Length);
   begin
      Written := 0;
      if not Target.Transaction_Open then
         Status := Destinations.Write_Failed;
         return;
      end if;

      if Target.Fail_Next_Allocation then
         Target.Fail_Next_Allocation := False;
         raise Storage_Error;
      end if;

      for Octet of Data loop
         Target.Data.Append (Octet);
      end loop;
      Written := Ada.Streams.Stream_Element_Count (Data'Length);
      Status := Destinations.Write_Succeeded;
   exception
      when Storage_Error =>
         while Ada.Streams.Stream_Element_Count (Target.Data.Length) > Original_Length loop
            Target.Data.Delete_Last;
         end loop;
         Target.Storage_Failed := True;
         Written := 0;
         Status := Destinations.Write_Failed;
   end Destination_Write;

   procedure Destination_Commit
     (Target : in out Destination;
      Status : out Destinations.Commit_Status)
   is
   begin
      if Target.Transaction_Open then
         Target.Committed := Ada.Streams.Stream_Element_Count (Target.Data.Length);
         Target.Transaction_Open := False;
         Status := Destinations.Commit_Succeeded;
      else
         Status := Destinations.Commit_Failed;
      end if;
   end Destination_Commit;

   procedure Destination_Abort
     (Target : in out Destination;
      Status : out Destinations.Abort_Status)
   is
   begin
      Target.Transaction_Open := False;
      Target.Committed := 0;
      Status := Destinations.Abort_Succeeded;
   end Destination_Abort;

   procedure Raise_If_Storage_Failed (Self : in out Writer) is
   begin
      if Self.Target.Storage_Failed then
         Self.Target.Storage_Failed := False;
         raise Storage_Error;
      end if;
   end Raise_If_Storage_Failed;

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
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Document (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Begin_Document;

   procedure Put_Unsigned
     (Self       : in out Writer;
      Value      : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Unsigned (Self.Core, Self.Target, Value, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Put_Unsigned;

   procedure Put_Negative_Argument
     (Self       : in out Writer;
      Argument   : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Negative_Argument (Self.Core, Self.Target, Argument, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Put_Negative_Argument;

   procedure Put_Signed
     (Self       : in out Writer;
      Value      : Interfaces.Integer_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Signed (Self.Core, Self.Target, Value, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Put_Signed;

   procedure Put_False (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.Put_False (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Put_False;

   procedure Put_True (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.Put_True (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Put_True;

   procedure Put_Null (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.Put_Null (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Put_Null;

   procedure Put_Undefined (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.Put_Undefined (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Put_Undefined;

   procedure Put_Simple
     (Self       : in out Writer;
      Value      : Values.Simple_Code;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Simple (Self.Core, Self.Target, Value, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Put_Simple;

   procedure Put_Float
     (Self       : in out Writer;
      Value      : Values.Float_Value;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Float (Self.Core, Self.Target, Value, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Put_Float;

   procedure Begin_Byte_String
     (Self       : in out Writer;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Byte_String (Self.Core, Self.Target, Length, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Begin_Byte_String;

   procedure Begin_Indefinite_Byte_String
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Indefinite_Byte_String (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Begin_Indefinite_Byte_String;

   procedure Begin_Byte_String_Chunk
     (Self       : in out Writer;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Byte_String_Chunk (Self.Core, Self.Target, Length, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Begin_Byte_String_Chunk;

   procedure Put_Byte_String_Fragment
     (Self       : in out Writer;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Byte_String_Fragment (Self.Core, Self.Target, Value, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Put_Byte_String_Fragment;

   procedure End_Byte_String_Chunk
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.End_Byte_String_Chunk (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end End_Byte_String_Chunk;

   procedure End_Byte_String (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.End_Byte_String (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end End_Byte_String;

   procedure Begin_Text_String
     (Self         : in out Writer;
      Octet_Length : Interfaces.Unsigned_64;
      Diagnostic   : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Text_String (Self.Core, Self.Target, Octet_Length, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Begin_Text_String;

   procedure Begin_Indefinite_Text_String
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Indefinite_Text_String (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Begin_Indefinite_Text_String;

   procedure Begin_Text_String_Chunk
     (Self         : in out Writer;
      Octet_Length : Interfaces.Unsigned_64;
      Diagnostic   : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Text_String_Chunk (Self.Core, Self.Target, Octet_Length, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Begin_Text_String_Chunk;

   procedure Put_Text_String_Fragment
     (Self       : in out Writer;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Text_String_Fragment (Self.Core, Self.Target, Value, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Put_Text_String_Fragment;

   procedure End_Text_String_Chunk
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.End_Text_String_Chunk (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end End_Text_String_Chunk;

   procedure End_Text_String (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.End_Text_String (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end End_Text_String;

   procedure Begin_Array
     (Self       : in out Writer;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Array (Self.Core, Self.Target, Length, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Begin_Array;

   procedure Begin_Indefinite_Array
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Indefinite_Array (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Begin_Indefinite_Array;

   procedure End_Array (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.End_Array (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end End_Array;

   procedure Begin_Map
     (Self       : in out Writer;
      Pair_Count : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Map (Self.Core, Self.Target, Pair_Count, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Begin_Map;

   procedure Begin_Indefinite_Map
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Indefinite_Map (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Begin_Indefinite_Map;

   procedure End_Map (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.End_Map (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end End_Map;

   procedure Begin_Tag
     (Self       : in out Writer;
      Number     : Values.Tag_Number;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Tag (Self.Core, Self.Target, Number, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Begin_Tag;

   procedure End_Tag (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.End_Tag (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end End_Tag;

   procedure Finish_Document (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.Finish_Document (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Finish_Document;

   procedure Abort_Document (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.Abort_Document (Self.Core, Self.Target, Diagnostic);
      Raise_If_Storage_Failed (Self);
   end Abort_Document;

   procedure Reset
     (Self       : in out Writer;
      Profile    : Profiles.Writer_Profile;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Reset (Self.Core, Profile, Diagnostic);
      if Engine.State (Self.Core) = Engine.Ready then
         Self.Target.Data.Clear;
         Self.Target.Committed := 0;
         Self.Target.Transaction_Open := False;
         Self.Target.Storage_Failed := False;
      end if;
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

   function Committed_Length
     (Self : Writer) return Ada.Streams.Stream_Element_Count is
     (Self.Target.Committed);

   function Output
     (Self : Writer) return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Self.Target.Committed));
   begin
      if Self.Target.Committed > 0 then
         for Count in 0 .. Self.Target.Committed - 1 loop
            Result (1 + Ada.Streams.Stream_Element_Offset (Count)) :=
              Self.Target.Data.Element (Natural (Count));
         end loop;
      end if;
      return Result;
   end Output;

end Flyology_CBOR.Allocating_Writing;
