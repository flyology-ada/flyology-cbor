--  Small executable examples embedded verbatim in the Flyology CBOR homepage.
--  The program parses and writes the unsigned value 42 through bounded public
--  surfaces, so the displayed calls cannot drift from the installed API.

with Ada.Streams;
with Flyology_CBOR.Bounded_Writing;
with Flyology_CBOR.Errors;
with Flyology_CBOR.Parsing;
with Flyology_CBOR.Profiles;

procedure Landing_Samples is
   package Errors renames Flyology_CBOR.Errors;
   package Parsing renames Flyology_CBOR.Parsing;
   package Profiles renames Flyology_CBOR.Profiles;
   package Writing renames Flyology_CBOR.Bounded_Writing;

   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Streams.Stream_Element_Count;
   use type Errors.Error_Code;
   use type Parsing.Drain_Stop;

   Parser_Profile : constant Profiles.Parser_Profile :=
     (Syntax     => (Family => Profiles.RFC_8949, Version => 1),
      Unicode    => (Family => Profiles.Unicode_Scalars, Version => 1),
      Acceptance => (Family => Profiles.Well_Formed_CBOR, Version => 1));

   Writer_Profile : constant Profiles.Writer_Profile :=
     (Syntax     => (Family => Profiles.RFC_8949, Version => 1),
      Unicode    => (Family => Profiles.Unicode_Scalars, Version => 1),
      Formatting => (Policy => Profiles.Ordinary_Compact, Version => 1));

   Parser       : Parsing.Parser (Maximum_Syntax_Depth => 0);
   Input        : constant Ada.Streams.Stream_Element_Array := [16#18#, 16#2A#];
   Events       : Parsing.Event_Array (1 .. 4);
   Parse_Result : Parsing.Drain_Result;

   Writer     : Writing.Writer (Capacity => 2, Maximum_Syntax_Depth => 0);
   Output     : Ada.Streams.Stream_Element_Array (5 .. 6) := [others => 0];
   Produced   : Ada.Streams.Stream_Element_Count;
   Diagnostic : Errors.Diagnostic;
begin
   Parsing.Initialize (Parser, Parser_Profile, Diagnostic);
   if Diagnostic.Code /= Errors.No_Error then
      raise Program_Error with "parser initialization failed";
   end if;

   --  BEGIN landing-parser
   --  The chunk is complete. Drain batches provisional events into the
   --  caller-owned event array and reports complete-document acceptance.
   Parsing.Drain
     (Self         => Parser,
      Input        => Input,
      End_Of_Input => True,
      Events       => Events,
      Result       => Parse_Result);
   --  END landing-parser

   if Parse_Result.Stop /= Parsing.Drain_Document_Complete then
      raise Program_Error with "CBOR value was not accepted";
   end if;

   Writing.Initialize (Writer, Writer_Profile, Diagnostic);
   if Diagnostic.Code /= Errors.No_Error then
      raise Program_Error with "writer initialization failed";
   end if;

   --  BEGIN landing-writer
   --  Finish_Document makes the staged complete value eligible. Copy_Output
   --  never exposes an incomplete prefix as successful output.
   Writing.Begin_Document (Writer, Diagnostic);
   Writing.Put_Unsigned (Writer, 42, Diagnostic);
   Writing.Finish_Document (Writer, Diagnostic);
   Writing.Copy_Output (Writer, Output, Produced, Diagnostic);
   --  END landing-writer

   if Diagnostic.Code /= Errors.No_Error or else Produced /= 2 or else Output /= Input
   then
      raise Program_Error with "bounded writer output differs";
   end if;
end Landing_Samples;
