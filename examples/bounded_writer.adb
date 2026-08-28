--  Complete bounded writer example. The writer owns unpublished staging and
--  makes output eligible only after Finish_Document succeeds.

with Ada.Streams;
with Flyology_CBOR.Bounded_Writing;
with Flyology_CBOR.Errors;
with Flyology_CBOR.Profiles;

procedure Bounded_Writer is
   package Writing renames Flyology_CBOR.Bounded_Writing;
   package Errors renames Flyology_CBOR.Errors;
   package Profiles renames Flyology_CBOR.Profiles;

   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Streams.Stream_Element_Count;
   use type Errors.Error_Code;

   procedure Check (Diagnostic : Errors.Diagnostic; Operation : String) is
   begin
      if Diagnostic.Code /= Errors.No_Error then
         raise Program_Error with Operation & " failed: " & Errors.Error_Code'Image (Diagnostic.Code);
      end if;
   end Check;

   --  BEGIN writer-setup
   Profile : constant Profiles.Writer_Profile :=
     (Syntax     => (Family => Profiles.RFC_8949, Version => 1),
      Unicode    => (Family => Profiles.Unicode_Scalars, Version => 1),
      Formatting => (Policy => Profiles.Ordinary_Compact, Version => 1));

   --  Capacity and syntax depth are application choices, not library defaults.
   Writer : Writing.Writer
     (Capacity             => 32,
      Maximum_Syntax_Depth => 1);

   Diagnostic : Errors.Diagnostic;
   Output     : Ada.Streams.Stream_Element_Array (20 .. 51) := [others => 0];
   Produced   : Ada.Streams.Stream_Element_Count;

   Name     : constant Ada.Streams.Stream_Element_Array := [16#6E#, 16#61#, 16#6D#, 16#65#];
   Ada_Text : constant Ada.Streams.Stream_Element_Array := [16#41#, 16#64#, 16#61#];
   N_Key    : constant Ada.Streams.Stream_Element_Array := [16#6E#];
   --  END writer-setup
begin
   Writing.Initialize (Writer, Profile, Diagnostic);
   Check (Diagnostic, "Initialize");

   --  BEGIN writer-calls
   Writing.Begin_Document (Writer, Diagnostic);
   Check (Diagnostic, "Begin_Document");
   Writing.Begin_Map (Writer, Pair_Count => 2, Diagnostic => Diagnostic);
   Check (Diagnostic, "Begin_Map");

   Writing.Begin_Text_String (Writer, Name'Length, Diagnostic);
   Writing.Put_Text_String_Fragment (Writer, Name, Diagnostic);
   Writing.End_Text_String (Writer, Diagnostic);

   Writing.Begin_Text_String (Writer, Ada_Text'Length, Diagnostic);
   Writing.Put_Text_String_Fragment (Writer, Ada_Text, Diagnostic);
   Writing.End_Text_String (Writer, Diagnostic);

   Writing.Begin_Text_String (Writer, N_Key'Length, Diagnostic);
   Writing.Put_Text_String_Fragment (Writer, N_Key, Diagnostic);
   Writing.End_Text_String (Writer, Diagnostic);
   Writing.Put_Unsigned (Writer, 1_000, Diagnostic);

   Writing.End_Map (Writer, Diagnostic);
   Check (Diagnostic, "End_Map");
   Writing.Finish_Document (Writer, Diagnostic);
   Check (Diagnostic, "Finish_Document");
   --  END writer-calls

   --  BEGIN writer-output
   Writing.Copy_Output (Writer, Output, Produced, Diagnostic);
   Check (Diagnostic, "Copy_Output");

   pragma Assert (Produced = 15);
   pragma Assert
     (Output (20 .. 34) =
        [16#A2#, 16#64#, 16#6E#, 16#61#, 16#6D#, 16#65#, 16#63#, 16#41#,
         16#64#, 16#61#, 16#61#, 16#6E#, 16#19#, 16#03#, 16#E8#]);
   --  END writer-output
end Bounded_Writer;
