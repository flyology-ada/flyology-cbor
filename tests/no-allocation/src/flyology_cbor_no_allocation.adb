pragma Restrictions (No_Allocators);
pragma Restrictions (No_Implicit_Heap_Allocations);

with Ada.Streams;
with Flyology_CBOR.Bounded_Writing;
with Flyology_CBOR.Errors;
with Flyology_CBOR.Parsing;
with Flyology_CBOR.Profiles;

procedure Flyology_CBOR_No_Allocation is
   use type Ada.Streams.Stream_Element_Count;
   use type Flyology_CBOR.Errors.Error_Code;
   use type Flyology_CBOR.Parsing.Step_Outcome;

   Parser     : Flyology_CBOR.Parsing.Parser (4);
   Writer     : Flyology_CBOR.Bounded_Writing.Writer (16, 4);
   Diagnostic : Flyology_CBOR.Errors.Diagnostic;
   Result     : Flyology_CBOR.Parsing.Step_Result;
   Output     : Ada.Streams.Stream_Element_Array (31 .. 46) := [others => 0];
   Produced   : Ada.Streams.Stream_Element_Count;
   Consumed   : Ada.Streams.Stream_Element_Count := 0;
   Empty      : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];

   Parser_Profile : constant Flyology_CBOR.Profiles.Parser_Profile :=
     (Syntax     => (Family => Flyology_CBOR.Profiles.RFC_8949, Version => 1),
      Unicode    => (Family => Flyology_CBOR.Profiles.Unicode_Scalars, Version => 1),
      Acceptance => (Family => Flyology_CBOR.Profiles.Well_Formed_CBOR, Version => 1));

   Writer_Profile : constant Flyology_CBOR.Profiles.Writer_Profile :=
     (Syntax     => (Family => Flyology_CBOR.Profiles.RFC_8949, Version => 1),
      Unicode    => (Family => Flyology_CBOR.Profiles.Unicode_Scalars, Version => 1),
      Formatting => (Policy => Flyology_CBOR.Profiles.Ordinary_Compact, Version => 1));
begin
   Flyology_CBOR.Bounded_Writing.Initialize (Writer, Writer_Profile, Diagnostic);
   pragma Assert (Diagnostic.Code = Flyology_CBOR.Errors.No_Error);
   Flyology_CBOR.Bounded_Writing.Begin_Document (Writer, Diagnostic);
   Flyology_CBOR.Bounded_Writing.Begin_Array (Writer, 1, Diagnostic);
   Flyology_CBOR.Bounded_Writing.Put_Unsigned (Writer, 24, Diagnostic);
   Flyology_CBOR.Bounded_Writing.End_Array (Writer, Diagnostic);
   Flyology_CBOR.Bounded_Writing.Finish_Document (Writer, Diagnostic);
   Flyology_CBOR.Bounded_Writing.Copy_Output (Writer, Output, Produced, Diagnostic);
   pragma Assert (Produced = 3);

   Flyology_CBOR.Parsing.Initialize (Parser, Parser_Profile, Diagnostic);
   loop
      if Consumed < Produced then
         Flyology_CBOR.Parsing.Step
           (Parser,
            Output
              (Output'First + Ada.Streams.Stream_Element_Offset (Consumed)
               .. Output'First + Ada.Streams.Stream_Element_Offset (Produced) - 1),
            True,
            Result);
      else
         Flyology_CBOR.Parsing.Step (Parser, Empty, True, Result);
      end if;
      Consumed := Consumed + Result.Consumed;
      exit when Result.Outcome = Flyology_CBOR.Parsing.Document_Complete;
      pragma Assert
        (Result.Outcome
         in Flyology_CBOR.Parsing.Event_Ready | Flyology_CBOR.Parsing.Need_Input);
   end loop;
end Flyology_CBOR_No_Allocation;
