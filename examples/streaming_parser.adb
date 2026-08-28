--  Complete streaming parser example with arbitrary Ada bounds and a split
--  text payload. Events remain provisional until document completion.

with Ada.Streams;
with Ada.Text_IO;
with Flyology_CBOR.Errors;
with Flyology_CBOR.Parsing;
with Flyology_CBOR.Profiles;

procedure Streaming_Parser is
   package Errors renames Flyology_CBOR.Errors;
   package Parsing renames Flyology_CBOR.Parsing;
   package Profiles renames Flyology_CBOR.Profiles;

   subtype Count is Ada.Streams.Stream_Element_Count;
   subtype Offset is Ada.Streams.Stream_Element_Offset;

   use type Count;
   use type Errors.Error_Code;
   use type Parsing.Drain_Stop;

   --  BEGIN parser-setup
   Profile : constant Profiles.Parser_Profile :=
     (Syntax     => (Family => Profiles.RFC_8949, Version => 1),
      Unicode    => (Family => Profiles.Unicode_Scalars, Version => 1),
      Acceptance => (Family => Profiles.Well_Formed_CBOR, Version => 1));

   --  The root map needs one syntax frame. This example gives the event array
   --  an arbitrary lower bound.
   Parser     : Parsing.Parser (Maximum_Syntax_Depth => 1);
   Events     : Parsing.Event_Array (-4 .. 1);
   Diagnostic : Errors.Diagnostic;
   Accepted   : Boolean := False;
   --  END parser-setup

   --  BEGIN parser-loop
   procedure Feed (Chunk : Ada.Streams.Stream_Element_Array; End_Of_Input : Boolean) is
      Used   : Count := 0;
      Result : Parsing.Drain_Result;
   begin
      loop
         declare
            First : constant Offset := Chunk'First + Offset (Used);
         begin
            if Used < Chunk'Length then
               Parsing.Drain (Parser, Chunk (First .. Chunk'Last), End_Of_Input, Events, Result);
            else
               declare
                  Empty : constant Ada.Streams.Stream_Element_Array (First .. First - 1) := [];
               begin
                  Parsing.Drain (Parser, Empty, End_Of_Input, Events, Result);
               end;
            end if;
         end;

         if Result.Produced > 0 then
            for Published in Count range 0 .. Result.Produced - 1 loop
               Ada.Text_IO.Put_Line
                 (Parsing.Event_Kind'Image (Parsing.Kind (Events (Events'First + Offset (Published)))));
            end loop;
         end if;

         Used := Used + Result.Consumed;
         case Result.Stop is
            when Parsing.Output_Full              => null;
            when Parsing.Drain_Need_Input         => return;
            when Parsing.Drain_Document_Complete  => Accepted := True; return;
            when Parsing.Drain_Failed | Parsing.Drain_Rejected =>
               raise Program_Error with Errors.Error_Code'Image (Result.Diagnostic.Code);
         end case;
      end loop;
   end Feed;
   --  END parser-loop

   First_Chunk : constant Ada.Streams.Stream_Element_Array (20 .. 27) :=
     [16#A2#, 16#64#, 16#6E#, 16#61#, 16#6D#, 16#65#, 16#63#, 16#41#];
   Final_Chunk : constant Ada.Streams.Stream_Element_Array (-10 .. -4) :=
     [16#64#, 16#61#, 16#61#, 16#6E#, 16#19#, 16#03#, 16#E8#];
begin
   Parsing.Initialize (Parser, Profile, Diagnostic);
   if Diagnostic.Code /= Errors.No_Error then
      raise Program_Error with Errors.Error_Code'Image (Diagnostic.Code);
   end if;

   Feed (First_Chunk, End_Of_Input => False);
   Feed (Final_Chunk, End_Of_Input => True);

   if not Accepted then
      raise Program_Error with "CBOR document was not accepted";
   end if;
end Streaming_Parser;
