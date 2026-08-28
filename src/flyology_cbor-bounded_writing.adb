package body Flyology_CBOR.Bounded_Writing is

   use type Ada.Streams.Stream_Element_Count;
   use type Engine.Writer_State;

   procedure Destination_Begin
     (Target : in out Destination;
      Status : out Destinations.Begin_Status)
   is
   begin
      Target.Length := 0;
      Target.Committed := 0;
      Target.Transaction_Open := True;
      Status := Destinations.Begin_Succeeded;
   end Destination_Begin;

   procedure Destination_Write
     (Target  : in out Destination;
      Data    : Ada.Streams.Stream_Element_Array;
      Written : out Ada.Streams.Stream_Element_Count;
      Status  : out Destinations.Write_Status)
   is
      Available : constant Ada.Streams.Stream_Element_Count :=
        Ada.Streams.Stream_Element_Count (Target.Capacity) - Target.Length;
      Accepted  : constant Ada.Streams.Stream_Element_Count :=
        Ada.Streams.Stream_Element_Count'Min
          (Available, Ada.Streams.Stream_Element_Count (Data'Length));
   begin
      Written := 0;
      if not Target.Transaction_Open then
         Status := Destinations.Write_Failed;
         return;
      end if;

      if Accepted > 0 then
         for Count in 0 .. Accepted - 1 loop
            Target.Data
              (1 + Natural (Target.Length + Count)) :=
              Data (Data'First + Ada.Streams.Stream_Element_Offset (Count));
         end loop;
      end if;
      Target.Length := Target.Length + Accepted;
      Written := Accepted;
      if Accepted = Ada.Streams.Stream_Element_Count (Data'Length) then
         Status := Destinations.Write_Succeeded;
      else
         Status := Destinations.Write_Exhausted;
      end if;
   end Destination_Write;

   procedure Destination_Commit
     (Target : in out Destination;
      Status : out Destinations.Commit_Status)
   is
   begin
      if Target.Transaction_Open then
         Target.Committed := Target.Length;
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
   end Begin_Document;

   procedure Put_Unsigned
     (Self       : in out Writer;
      Value      : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Unsigned (Self.Core, Self.Target, Value, Diagnostic);
   end Put_Unsigned;

   procedure Put_Negative_Argument
     (Self       : in out Writer;
      Argument   : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Negative_Argument (Self.Core, Self.Target, Argument, Diagnostic);
   end Put_Negative_Argument;

   procedure Put_Signed
     (Self       : in out Writer;
      Value      : Interfaces.Integer_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Signed (Self.Core, Self.Target, Value, Diagnostic);
   end Put_Signed;

   procedure Put_False (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.Put_False (Self.Core, Self.Target, Diagnostic);
   end Put_False;

   procedure Put_True (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.Put_True (Self.Core, Self.Target, Diagnostic);
   end Put_True;

   procedure Put_Null (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.Put_Null (Self.Core, Self.Target, Diagnostic);
   end Put_Null;

   procedure Put_Undefined (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.Put_Undefined (Self.Core, Self.Target, Diagnostic);
   end Put_Undefined;

   procedure Put_Simple
     (Self       : in out Writer;
      Value      : Values.Simple_Code;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Simple (Self.Core, Self.Target, Value, Diagnostic);
   end Put_Simple;

   procedure Put_Float
     (Self       : in out Writer;
      Value      : Values.Float_Value;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Float (Self.Core, Self.Target, Value, Diagnostic);
   end Put_Float;

   procedure Begin_Byte_String
     (Self       : in out Writer;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Byte_String (Self.Core, Self.Target, Length, Diagnostic);
   end Begin_Byte_String;

   procedure Begin_Indefinite_Byte_String
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Indefinite_Byte_String (Self.Core, Self.Target, Diagnostic);
   end Begin_Indefinite_Byte_String;

   procedure Begin_Byte_String_Chunk
     (Self       : in out Writer;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Byte_String_Chunk (Self.Core, Self.Target, Length, Diagnostic);
   end Begin_Byte_String_Chunk;

   procedure Put_Byte_String_Fragment
     (Self       : in out Writer;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Byte_String_Fragment (Self.Core, Self.Target, Value, Diagnostic);
   end Put_Byte_String_Fragment;

   procedure End_Byte_String_Chunk
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.End_Byte_String_Chunk (Self.Core, Self.Target, Diagnostic);
   end End_Byte_String_Chunk;

   procedure End_Byte_String (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.End_Byte_String (Self.Core, Self.Target, Diagnostic);
   end End_Byte_String;

   procedure Begin_Text_String
     (Self         : in out Writer;
      Octet_Length : Interfaces.Unsigned_64;
      Diagnostic   : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Text_String (Self.Core, Self.Target, Octet_Length, Diagnostic);
   end Begin_Text_String;

   procedure Begin_Indefinite_Text_String
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Indefinite_Text_String (Self.Core, Self.Target, Diagnostic);
   end Begin_Indefinite_Text_String;

   procedure Begin_Text_String_Chunk
     (Self         : in out Writer;
      Octet_Length : Interfaces.Unsigned_64;
      Diagnostic   : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Text_String_Chunk (Self.Core, Self.Target, Octet_Length, Diagnostic);
   end Begin_Text_String_Chunk;

   procedure Put_Text_String_Fragment
     (Self       : in out Writer;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Put_Text_String_Fragment (Self.Core, Self.Target, Value, Diagnostic);
   end Put_Text_String_Fragment;

   procedure End_Text_String_Chunk
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.End_Text_String_Chunk (Self.Core, Self.Target, Diagnostic);
   end End_Text_String_Chunk;

   procedure End_Text_String (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.End_Text_String (Self.Core, Self.Target, Diagnostic);
   end End_Text_String;

   procedure Begin_Array
     (Self       : in out Writer;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Array (Self.Core, Self.Target, Length, Diagnostic);
   end Begin_Array;

   procedure Begin_Indefinite_Array
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Indefinite_Array (Self.Core, Self.Target, Diagnostic);
   end Begin_Indefinite_Array;

   procedure End_Array (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.End_Array (Self.Core, Self.Target, Diagnostic);
   end End_Array;

   procedure Begin_Map
     (Self       : in out Writer;
      Pair_Count : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Map (Self.Core, Self.Target, Pair_Count, Diagnostic);
   end Begin_Map;

   procedure Begin_Indefinite_Map
     (Self : in out Writer; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Indefinite_Map (Self.Core, Self.Target, Diagnostic);
   end Begin_Indefinite_Map;

   procedure End_Map (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.End_Map (Self.Core, Self.Target, Diagnostic);
   end End_Map;

   procedure Begin_Tag
     (Self       : in out Writer;
      Number     : Values.Tag_Number;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Begin_Tag (Self.Core, Self.Target, Number, Diagnostic);
   end Begin_Tag;

   procedure End_Tag (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.End_Tag (Self.Core, Self.Target, Diagnostic);
   end End_Tag;

   procedure Finish_Document (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.Finish_Document (Self.Core, Self.Target, Diagnostic);
   end Finish_Document;

   procedure Abort_Document (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Engine.Abort_Document (Self.Core, Self.Target, Diagnostic);
   end Abort_Document;

   procedure Reset
     (Self       : in out Writer;
      Profile    : Profiles.Writer_Profile;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Engine.Reset (Self.Core, Profile, Diagnostic);
      if Engine.State (Self.Core) = Engine.Ready then
         Self.Target.Length := 0;
         Self.Target.Committed := 0;
         Self.Target.Transaction_Open := False;
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

   function Staged_Length
     (Self : Writer) return Ada.Streams.Stream_Element_Count is
     (Self.Target.Length);

   function Committed_Length
     (Self : Writer) return Ada.Streams.Stream_Element_Count is
     (Self.Target.Committed);

   procedure Copy_Output
     (Self       : Writer;
      Target     : in out Ada.Streams.Stream_Element_Array;
      Produced   : out Ada.Streams.Stream_Element_Count;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Produced := 0;
      if State (Self) /= Completed then
         Errors.Clear (Diagnostic);
         Diagnostic.Code := Errors.Invalid_State;
         Diagnostic.Coordinate := Errors.Staged_Output_Byte;
         Diagnostic.Offset := Interfaces.Unsigned_64 (Self.Target.Committed);
         return;
      elsif Ada.Streams.Stream_Element_Count (Target'Length) < Self.Target.Committed then
         Errors.Clear (Diagnostic);
         Diagnostic.Code := Errors.Destination_Exhausted;
         Diagnostic.Coordinate := Errors.Staged_Output_Byte;
         Diagnostic.Offset := Interfaces.Unsigned_64 (Target'Length);
         return;
      end if;

      if Self.Target.Committed > 0 then
         for Count in 0 .. Self.Target.Committed - 1 loop
            Target (Target'First + Ada.Streams.Stream_Element_Offset (Count)) :=
              Self.Target.Data (1 + Natural (Count));
         end loop;
      end if;
      Produced := Self.Target.Committed;
      Errors.Clear (Diagnostic);
   end Copy_Output;

end Flyology_CBOR.Bounded_Writing;
