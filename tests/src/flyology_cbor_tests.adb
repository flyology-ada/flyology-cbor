with Ada.Streams;
with Ada.Text_IO;
with Flyology_CBOR.Allocating_Writing;
with Flyology_CBOR.Bounded_Writing;
with Flyology_CBOR.Destinations;
with Flyology_CBOR.Errors;
with Flyology_CBOR.Numbers.Binary64;
with Flyology_CBOR.Numbers.Signed_Integers;
with Flyology_CBOR.Numbers.Unsigned_Integers;
with Flyology_CBOR.Parsing;
with Flyology_CBOR.Profiles;
with Flyology_CBOR.Values;
with Flyology_CBOR.Writing;
with Interfaces;

procedure Flyology_CBOR_Tests is
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Count;
   use type Flyology_CBOR.Bounded_Writing.Writer_State;
   use type Flyology_CBOR.Errors.Error_Code;
   use type Flyology_CBOR.Errors.Coordinate_Kind;
   use type Flyology_CBOR.Numbers.Binary64.Conversion_Status;
   use type Flyology_CBOR.Parsing.Drain_Stop;
   use type Flyology_CBOR.Parsing.Event_Kind;
   use type Flyology_CBOR.Parsing.Fragment_Representation;
   use type Flyology_CBOR.Parsing.Parser_State;
   use type Flyology_CBOR.Parsing.Step_Outcome;
   use type Flyology_CBOR.Parsing.Slice_Status;
   use type Flyology_CBOR.Values.Float_Category;
   use type Flyology_CBOR.Values.Float_Construction_Status;
   use type Flyology_CBOR.Values.Float_Width;
   use type Flyology_CBOR.Values.Length_Kind;
   use type Interfaces.Integer_64;
   use type Interfaces.Integer_128;
   use type Interfaces.Unsigned_64;

   subtype Byte_Array is Ada.Streams.Stream_Element_Array;
   subtype Offset is Ada.Streams.Stream_Element_Offset;

   Parser_Profile : constant Flyology_CBOR.Profiles.Parser_Profile :=
     (Syntax     => (Family => Flyology_CBOR.Profiles.RFC_8949, Version => 1),
      Unicode    => (Family => Flyology_CBOR.Profiles.Unicode_Scalars, Version => 1),
      Acceptance => (Family => Flyology_CBOR.Profiles.Well_Formed_CBOR, Version => 1));

   Writer_Profile : constant Flyology_CBOR.Profiles.Writer_Profile :=
     (Syntax     => (Family => Flyology_CBOR.Profiles.RFC_8949, Version => 1),
      Unicode    => (Family => Flyology_CBOR.Profiles.Unicode_Scalars, Version => 1),
      Formatting => (Policy => Flyology_CBOR.Profiles.Ordinary_Compact, Version => 1));

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   procedure Check_Clear
     (Diagnostic : Flyology_CBOR.Errors.Diagnostic;
      Context    : String)
   is
   begin
      Check (Diagnostic.Code = Flyology_CBOR.Errors.No_Error, Context);
   end Check_Clear;

   type External_Destination is limited record
      Buffer      : Byte_Array (1 .. 32) := [others => 0];
      Length      : Ada.Streams.Stream_Element_Count := 0;
      Begun       : Boolean := False;
      Published   : Boolean := False;
      Fail_Commit : Boolean := False;
      Fail_Abort  : Boolean := False;
   end record;

   procedure External_Begin
     (Target : in out External_Destination;
      Status : out Flyology_CBOR.Destinations.Begin_Status)
   is
   begin
      Target.Length := 0;
      Target.Begun := True;
      Target.Published := False;
      Status := Flyology_CBOR.Destinations.Begin_Succeeded;
   end External_Begin;

   procedure External_Write
     (Target  : in out External_Destination;
      Data    : Byte_Array;
      Written : out Ada.Streams.Stream_Element_Count;
      Status  : out Flyology_CBOR.Destinations.Write_Status)
   is
   begin
      if not Target.Begun
        or else Ada.Streams.Stream_Element_Count (Data'Length) > 32 - Target.Length
      then
         Written := 0;
         Status := Flyology_CBOR.Destinations.Write_Failed;
         return;
      end if;
      for Octet of Data loop
         Target.Length := Target.Length + 1;
         Target.Buffer (Offset (Target.Length)) := Octet;
      end loop;
      Written := Ada.Streams.Stream_Element_Count (Data'Length);
      Status := Flyology_CBOR.Destinations.Write_Succeeded;
   end External_Write;

   procedure External_Commit
     (Target : in out External_Destination;
      Status : out Flyology_CBOR.Destinations.Commit_Status)
   is
   begin
      if Target.Fail_Commit then
         Status := Flyology_CBOR.Destinations.Commit_Failed;
      else
         Target.Published := True;
         Target.Begun := False;
         Status := Flyology_CBOR.Destinations.Commit_Succeeded;
      end if;
   end External_Commit;

   procedure External_Abort
     (Target : in out External_Destination;
      Status : out Flyology_CBOR.Destinations.Abort_Status)
   is
   begin
      Target.Begun := False;
      if Target.Fail_Abort then
         Status := Flyology_CBOR.Destinations.Abort_Failed;
      else
         Status := Flyology_CBOR.Destinations.Abort_Succeeded;
      end if;
   end External_Abort;

   package External_Writing is new Flyology_CBOR.Writing
     (Destination_Type   => External_Destination,
      Destination_Begin  => External_Begin,
      Destination_Write  => External_Write,
      Destination_Commit => External_Commit,
      Destination_Abort  => External_Abort);

   procedure Test_Values_And_Numbers is
      package Signed_64_Conversions is new
        Flyology_CBOR.Numbers.Signed_Integers (Interfaces.Integer_64);
      package Unsigned_64_Conversions is new
        Flyology_CBOR.Numbers.Unsigned_Integers (Interfaces.Unsigned_64);
      package Signed_128_Conversions is new
        Flyology_CBOR.Numbers.Signed_Integers (Interfaces.Integer_128);

      use type Signed_64_Conversions.Conversion_Status;
      use type Unsigned_64_Conversions.Conversion_Status;
      use type Signed_128_Conversions.Conversion_Status;

      Float_Item   : Flyology_CBOR.Values.Float_Value;
      Float_Status : Flyology_CBOR.Values.Float_Construction_Status;
      Binary       : Flyology_CBOR.Numbers.Binary64.Conversion_Result;
      Signed       : Signed_64_Conversions.Conversion_Result;
      Unsigned     : Unsigned_64_Conversions.Conversion_Result;
      Signed_128   : Signed_128_Conversions.Conversion_Result;
      Length       : constant Flyology_CBOR.Values.Item_Length :=
        Flyology_CBOR.Values.Definite (Interfaces.Unsigned_64'Last);
   begin
      Check
        (Flyology_CBOR.Values.Kind (Length) = Flyology_CBOR.Values.Definite_Length,
         "definite length kind");
      Check
        (Flyology_CBOR.Values.Length (Length) = Interfaces.Unsigned_64'Last,
         "definite U64 length");

      Signed_64_Conversions.Convert
        (Flyology_CBOR.Values.Negative (Interfaces.Unsigned_64 (Interfaces.Integer_64'Last)),
         Signed);
      Check
        (Signed_64_Conversions.Status (Signed) = Signed_64_Conversions.Converted,
         "signed minimum converts");
      Check
        (Signed_64_Conversions.Value (Signed) = Interfaces.Integer_64'First,
         "signed minimum value");
      Signed_64_Conversions.Convert
        (Flyology_CBOR.Values.Negative (Interfaces.Unsigned_64'Last), Signed);
      Check
        (Signed_64_Conversions.Status (Signed) = Signed_64_Conversions.Below_Range,
         "negative U64 argument range check");
      Unsigned_64_Conversions.Convert (Flyology_CBOR.Values.Negative (0), Unsigned);
      Check
        (Unsigned_64_Conversions.Status (Unsigned)
         = Unsigned_64_Conversions.Negative_Value,
         "negative to unsigned rejected");
      Signed_128_Conversions.Convert
        (Flyology_CBOR.Values.Unsigned (Interfaces.Unsigned_64'Last), Signed_128);
      Check
        (Signed_128_Conversions.Status (Signed_128) = Signed_128_Conversions.Converted,
         "unsigned U64 converts to signed 128");
      Check
        (Signed_128_Conversions.Value (Signed_128)
         = Interfaces.Integer_128 (Interfaces.Unsigned_64'Last),
         "signed 128 conversion value");

      Flyology_CBOR.Values.Make_Float
        (Flyology_CBOR.Values.Binary16, 16#3C00#, Float_Item, Float_Status);
      Check
        (Float_Status = Flyology_CBOR.Values.Float_Constructed,
         "binary16 construction");
      Flyology_CBOR.Numbers.Binary64.Convert (Float_Item, Binary);
      Check
        (Flyology_CBOR.Numbers.Binary64.Status (Binary)
         = Flyology_CBOR.Numbers.Binary64.Converted_Finite,
         "binary16 finite promotion");
      Check
        (Flyology_CBOR.Numbers.Binary64.Value (Binary) = 16#3FF0_0000_0000_0000#,
         "binary16 one promotes exactly");

      Flyology_CBOR.Values.Make_Float
        (Flyology_CBOR.Values.Binary16, 16#0001#, Float_Item, Float_Status);
      Flyology_CBOR.Numbers.Binary64.Convert (Float_Item, Binary);
      Check
        (Flyology_CBOR.Numbers.Binary64.Value (Binary) = 16#3E70_0000_0000_0000#,
         "binary16 minimum subnormal promotes exactly");

      Flyology_CBOR.Values.Make_Float
        (Flyology_CBOR.Values.Binary32, 16#7F80_0000#, Float_Item, Float_Status);
      Check
        (Flyology_CBOR.Values.Category (Float_Item)
         = Flyology_CBOR.Values.Positive_Infinity,
         "float category");
      Flyology_CBOR.Numbers.Binary64.Convert (Float_Item, Binary);
      Check
        (Flyology_CBOR.Numbers.Binary64.Status (Binary)
         = Flyology_CBOR.Numbers.Binary64.Converted_Positive_Infinity,
         "infinity category conversion");

      Flyology_CBOR.Values.Make_Float
        (Flyology_CBOR.Values.Binary16, 16#1_0000#, Float_Item, Float_Status);
      Check
        (Float_Status = Flyology_CBOR.Values.Bits_Out_Of_Range,
         "float high bits rejected");
   end Test_Values_And_Numbers;

   procedure Test_Parser_Transcript is
      Input : constant Byte_Array (42 .. 55) :=
        [16#9F#,
         16#C1#,
         16#18#,
         16#18#,
         16#64#,
         16#F0#,
         16#9F#,
         16#92#,
         16#A9#,
         16#A1#,
         16#01#,
         16#F5#,
         16#FF#,
         16#00#];
      Expected : constant array (Positive range <>) of Flyology_CBOR.Parsing.Event_Kind :=
        [Flyology_CBOR.Parsing.Document_Begin,
         Flyology_CBOR.Parsing.Array_Begin,
         Flyology_CBOR.Parsing.Tag_Begin,
         Flyology_CBOR.Parsing.Unsigned_Value,
         Flyology_CBOR.Parsing.Tag_End,
         Flyology_CBOR.Parsing.Text_String_Begin,
         Flyology_CBOR.Parsing.Text_String_Fragment,
         Flyology_CBOR.Parsing.Text_String_End,
         Flyology_CBOR.Parsing.Map_Begin,
         Flyology_CBOR.Parsing.Unsigned_Value,
         Flyology_CBOR.Parsing.True_Value,
         Flyology_CBOR.Parsing.Map_End,
         Flyology_CBOR.Parsing.Array_End,
         Flyology_CBOR.Parsing.Document_End];
      Parser     : Flyology_CBOR.Parsing.Parser (8);
      Diagnostic : Flyology_CBOR.Errors.Diagnostic;
      Result     : Flyology_CBOR.Parsing.Step_Result;
      Cursor     : Offset := Input'First;
      Seen       : Natural := 0;
      Slice      : Flyology_CBOR.Parsing.Chunk_Range;
      Status     : Flyology_CBOR.Parsing.Slice_Status;
      Empty      : constant Byte_Array (1 .. 0) := [];
   begin
      Flyology_CBOR.Parsing.Initialize (Parser, Parser_Profile, Diagnostic);
      Check_Clear (Diagnostic, "parser initialize");

      while Cursor <= Input'Last - 1 loop
         Flyology_CBOR.Parsing.Step
           (Parser, Input (Cursor .. Cursor), False, Result);
         if Result.Outcome = Flyology_CBOR.Parsing.Event_Ready then
            Seen := Seen + 1;
            Check
              (Flyology_CBOR.Parsing.Kind (Result.Item) = Expected (Seen),
               "split transcript event" & Natural'Image (Seen));
            if Flyology_CBOR.Parsing.Kind (Result.Item)
              = Flyology_CBOR.Parsing.Text_String_Fragment
            then
               Check
                 (Flyology_CBOR.Parsing.Fragment_Kind (Result.Item)
                  = Flyology_CBOR.Parsing.Inline_Text_Scalar,
                  "split UTF-8 owns inline scalar");
               Check
                 (Flyology_CBOR.Parsing.Inline_Text (Result.Item).Length = 4,
                  "inline scalar length");
            elsif Flyology_CBOR.Parsing.Has_Raw_Slice (Result.Item) then
               Flyology_CBOR.Parsing.Resolve_Raw_Range
                 (Result.Item,
                  Result.Input_Origin,
                  1,
                  Slice,
                  Status);
               Check
                 (Status = Flyology_CBOR.Parsing.Slice_Resolved,
                  "raw range resolves against producing window");
               Check (Slice.First_Count = 0, "raw range begins in producing window");
            end if;
         elsif Result.Outcome = Flyology_CBOR.Parsing.Need_Input then
            null;
         else
            Check (False, "unexpected split parser outcome");
         end if;

         if Result.Consumed = 1 then
            Cursor := Cursor + 1;
         else
            Check (Result.Consumed = 0, "one-byte split consumed count");
         end if;
      end loop;

      loop
         Flyology_CBOR.Parsing.Step (Parser, Empty, True, Result);
         exit when Result.Outcome = Flyology_CBOR.Parsing.Document_Complete;
         Check
           (Result.Outcome = Flyology_CBOR.Parsing.Event_Ready,
            "terminal synthetic event");
         Seen := Seen + 1;
         Check
           (Flyology_CBOR.Parsing.Kind (Result.Item) = Expected (Seen),
            "terminal transcript event");
      end loop;
      Check (Seen = Expected'Length, "complete transcript length");
      Check
        (Flyology_CBOR.Parsing.State (Parser) = Flyology_CBOR.Parsing.Completed,
         "parser completed state");
   end Test_Parser_Transcript;

   procedure Expect_Parser_Error
     (Input             : Byte_Array;
      Expected          : Flyology_CBOR.Errors.Error_Code;
      Expected_Offset   : Interfaces.Unsigned_64;
      Expected_Construct : Interfaces.Unsigned_64)
   is
      Parser     : Flyology_CBOR.Parsing.Parser (8);
      Diagnostic : Flyology_CBOR.Errors.Diagnostic;
      Result     : Flyology_CBOR.Parsing.Step_Result;
      Consumed   : Ada.Streams.Stream_Element_Count := 0;
      Empty      : constant Byte_Array (1 .. 0) := [];
   begin
      Flyology_CBOR.Parsing.Initialize (Parser, Parser_Profile, Diagnostic);
      loop
         if Consumed < Ada.Streams.Stream_Element_Count (Input'Length) then
            Flyology_CBOR.Parsing.Step
              (Parser,
               Input
                 (Input'First + Ada.Streams.Stream_Element_Offset (Consumed) .. Input'Last),
               True,
               Result);
         else
            Flyology_CBOR.Parsing.Step (Parser, Empty, True, Result);
         end if;
         Consumed := Consumed + Result.Consumed;
         exit when Result.Outcome = Flyology_CBOR.Parsing.Step_Failed;
         Check
           (Result.Outcome in Flyology_CBOR.Parsing.Event_Ready | Flyology_CBOR.Parsing.Need_Input,
            "malformed case terminates in failure");
      end loop;
      Check (Result.Diagnostic.Code = Expected, "parser diagnostic code");
      Check (Result.Diagnostic.Offset = Expected_Offset, "parser proving offset");
      Check (Result.Diagnostic.Has_Construct_Offset, "parser construct offset eligible");
      Check
        (Result.Diagnostic.Construct_Offset = Expected_Construct,
         "parser construct offset");
   end Expect_Parser_Error;

   procedure Test_Parser_Failures_And_Drain is
      Events     : Flyology_CBOR.Parsing.Event_Array (17 .. 20);
      Parser     : Flyology_CBOR.Parsing.Parser (4);
      Diagnostic : Flyology_CBOR.Errors.Diagnostic;
      Result     : Flyology_CBOR.Parsing.Drain_Result;
      Input      : constant Byte_Array (91 .. 93) := [16#82#, 1, 2];
      Empty      : constant Byte_Array (1 .. 0) := [];
   begin
      Expect_Parser_Error ([16#1C#], Flyology_CBOR.Errors.Reserved_Additional_Information, 0, 0);
      Expect_Parser_Error ([16#1F#], Flyology_CBOR.Errors.Invalid_Indefinite_Item, 0, 0);
      Expect_Parser_Error ([16#BF#, 1, 16#FF#], Flyology_CBOR.Errors.Odd_Map, 2, 2);
      Expect_Parser_Error ([16#C1#], Flyology_CBOR.Errors.Truncated_Input, 1, 1);
      Expect_Parser_Error ([16#62#, 16#C2#, 16#20#], Flyology_CBOR.Errors.Invalid_UTF8, 2, 2);
      Expect_Parser_Error ([16#63#, 16#C2#], Flyology_CBOR.Errors.Truncated_Input, 2, 1);
      Expect_Parser_Error
        ([16#63#, 16#C2#, 16#20#], Flyology_CBOR.Errors.Truncated_Input, 3, 1);

      declare
         Split_Parser : Flyology_CBOR.Parsing.Parser (2);
         Split_Result : Flyology_CBOR.Parsing.Step_Result;
         Split_Input  : constant Byte_Array (31 .. 33) := [16#63#, 16#C2#, 16#20#];
      begin
         Flyology_CBOR.Parsing.Initialize (Split_Parser, Parser_Profile, Diagnostic);
         Flyology_CBOR.Parsing.Step (Split_Parser, Empty, False, Split_Result);
         Flyology_CBOR.Parsing.Step (Split_Parser, Split_Input, False, Split_Result);
         Check (Split_Result.Consumed = 1, "split truncation consumes text head");
         Flyology_CBOR.Parsing.Step
           (Split_Parser, Split_Input (32 .. 33), False, Split_Result);
         Check
           (Split_Result.Outcome = Flyology_CBOR.Parsing.Need_Input,
            "malformed text waits for truncation precedence");
         Flyology_CBOR.Parsing.Step (Split_Parser, Empty, True, Split_Result);
         Check
           (Split_Result.Outcome = Flyology_CBOR.Parsing.Step_Failed
            and then Split_Result.Diagnostic.Code = Flyology_CBOR.Errors.Truncated_Input
            and then Split_Result.Diagnostic.Offset = 3,
            "split truncation matches monolithic precedence");
      end;
      Expect_Parser_Error ([1, 2], Flyology_CBOR.Errors.Trailing_Input, 1, 1);

      Flyology_CBOR.Parsing.Initialize (Parser, Parser_Profile, Diagnostic);
      Events := [others => <>];
      Flyology_CBOR.Parsing.Drain (Parser, Input, True, Events, Result);
      Check (Result.Produced = 4, "drain exact event capacity");
      Check (Result.Stop = Flyology_CBOR.Parsing.Output_Full, "drain output full");
      Check
        (Flyology_CBOR.Parsing.Kind (Events (17)) = Flyology_CBOR.Parsing.Document_Begin,
         "drain first event");
      Check
        (Flyology_CBOR.Parsing.Kind (Events (20)) = Flyology_CBOR.Parsing.Unsigned_Value,
         "drain fourth event");

      declare
         Null_Events : Flyology_CBOR.Parsing.Event_Array (1 .. 0);
      begin
         Flyology_CBOR.Parsing.Drain (Parser, Input (1 .. 0), True, Null_Events, Result);
         Check (Result.Stop = Flyology_CBOR.Parsing.Output_Full, "null drain output full");
         Check (Result.Consumed = 0 and then Result.Produced = 0, "null drain no mutation");
      end;
   end Test_Parser_Failures_And_Drain;

   procedure Test_All_Initial_Octets is
      Empty : constant Byte_Array (1 .. 0) := [];
   begin
      for Number in 0 .. 255 loop
         declare
            Parser     : Flyology_CBOR.Parsing.Parser (4);
            Diagnostic : Flyology_CBOR.Errors.Diagnostic;
            Result     : Flyology_CBOR.Parsing.Step_Result;
            Input      : constant Byte_Array (113 .. 113) :=
              [113 => Ada.Streams.Stream_Element (Number)];
            Consumed   : Ada.Streams.Stream_Element_Count := 0;
            Calls      : Natural := 0;
         begin
            Flyology_CBOR.Parsing.Initialize (Parser, Parser_Profile, Diagnostic);
            loop
               Calls := Calls + 1;
               Check (Calls <= 20, "initial-octet parser progress");
               if Consumed = 0 then
                  Flyology_CBOR.Parsing.Step (Parser, Input, True, Result);
               else
                  Flyology_CBOR.Parsing.Step (Parser, Empty, True, Result);
               end if;
               Consumed := Consumed + Result.Consumed;
               exit when Result.Outcome
                 in Flyology_CBOR.Parsing.Document_Complete
                    | Flyology_CBOR.Parsing.Step_Failed;
               Check
                 (Result.Outcome
                  in Flyology_CBOR.Parsing.Event_Ready | Flyology_CBOR.Parsing.Need_Input,
                  "initial-octet definite outcome");
            end loop;
         end;
      end loop;
   end Test_All_Initial_Octets;

   procedure Test_Bounded_Writer is
      Writer     : Flyology_CBOR.Bounded_Writing.Writer (64, 8);
      Diagnostic : Flyology_CBOR.Errors.Diagnostic;
      Float_Item : Flyology_CBOR.Values.Float_Value;
      Status     : Flyology_CBOR.Values.Float_Construction_Status;
      Output     : Byte_Array (33 .. 96) := [others => 16#AA#];
      Produced   : Ada.Streams.Stream_Element_Count;
      Expected   : constant Byte_Array (1 .. 13) :=
        [16#9F#,
         16#C1#,
         16#18#,
         16#18#,
         16#64#,
         16#F0#,
         16#9F#,
         16#92#,
         16#A9#,
         16#A1#,
         16#01#,
         16#F5#,
         16#FF#];
      Text : constant Byte_Array (7 .. 10) := [16#F0#, 16#9F#, 16#92#, 16#A9#];
   begin
      Flyology_CBOR.Values.Make_Float
        (Flyology_CBOR.Values.Binary64, 0, Float_Item, Status);
      Flyology_CBOR.Bounded_Writing.Initialize (Writer, Writer_Profile, Diagnostic);
      Check_Clear (Diagnostic, "bounded initialize");
      Flyology_CBOR.Bounded_Writing.Begin_Document (Writer, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Begin_Indefinite_Array (Writer, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Begin_Tag (Writer, 1, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Put_Unsigned (Writer, 24, Diagnostic);
      Flyology_CBOR.Bounded_Writing.End_Tag (Writer, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Begin_Text_String (Writer, 4, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Put_Text_String_Fragment
        (Writer, Text (7 .. 8), Diagnostic);
      Flyology_CBOR.Bounded_Writing.Put_Text_String_Fragment
        (Writer, Text (9 .. 10), Diagnostic);
      Flyology_CBOR.Bounded_Writing.End_Text_String (Writer, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Begin_Map (Writer, 1, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Put_Unsigned (Writer, 1, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Put_True (Writer, Diagnostic);
      Flyology_CBOR.Bounded_Writing.End_Map (Writer, Diagnostic);
      Flyology_CBOR.Bounded_Writing.End_Array (Writer, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Finish_Document (Writer, Diagnostic);
      Check_Clear (Diagnostic, "bounded finish");
      Check
        (Flyology_CBOR.Bounded_Writing.Committed_Length (Writer) = Expected'Length,
         "bounded committed length");
      Flyology_CBOR.Bounded_Writing.Copy_Output
        (Writer, Output, Produced, Diagnostic);
      Check_Clear (Diagnostic, "bounded copy");
      Check (Produced = Expected'Length, "bounded produced");
      for Count in 0 .. Produced - 1 loop
         Check
           (Output (Output'First + Offset (Count)) = Expected (Expected'First + Offset (Count)),
            "bounded byte" & Ada.Streams.Stream_Element_Count'Image (Count));
      end loop;
      Check (Output (Output'First + Offset (Produced)) = 16#AA#, "copy suffix unchanged");
   end Test_Bounded_Writer;

   procedure Test_Writer_Lifecycle is
      Tiny       : Flyology_CBOR.Bounded_Writing.Writer (1, 2);
      Diagnostic : Flyology_CBOR.Errors.Diagnostic;
   begin
      Flyology_CBOR.Bounded_Writing.Initialize (Tiny, Writer_Profile, Diagnostic);
      Check (Flyology_CBOR.Bounded_Writing.Staged_Length (Tiny) = 0, "initial staged");
      Flyology_CBOR.Bounded_Writing.Begin_Document (Tiny, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Put_Unsigned (Tiny, 1_000, Diagnostic);
      Check
        (Diagnostic.Code = Flyology_CBOR.Errors.Destination_Exhausted,
         "bounded exhaustion");
      Check
        (Flyology_CBOR.Bounded_Writing.State (Tiny) = Flyology_CBOR.Bounded_Writing.Failed,
         "exhaustion poisons");
      Check (Flyology_CBOR.Bounded_Writing.Staged_Length (Tiny) = 1, "failed staged prefix");
      Flyology_CBOR.Bounded_Writing.Reset (Tiny, Writer_Profile, Diagnostic);
      Check_Clear (Diagnostic, "reset after poison");
      Check (Flyology_CBOR.Bounded_Writing.Staged_Length (Tiny) = 0, "reset staged length");
      Flyology_CBOR.Bounded_Writing.Begin_Document (Tiny, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Put_Unsigned (Tiny, 1, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Abort_Document (Tiny, Diagnostic);
      Check_Clear (Diagnostic, "explicit abort");
      Check (Flyology_CBOR.Bounded_Writing.Staged_Length (Tiny) = 1, "abort staged prefix");
      Check
        (Flyology_CBOR.Bounded_Writing.State (Tiny) = Flyology_CBOR.Bounded_Writing.Aborted,
         "abort state");
      Flyology_CBOR.Bounded_Writing.Reset (Tiny, Writer_Profile, Diagnostic);
      Check (Flyology_CBOR.Bounded_Writing.Staged_Length (Tiny) = 0, "abort reset staged");
   end Test_Writer_Lifecycle;

   procedure Test_Writer_Failures is
      Diagnostic : Flyology_CBOR.Errors.Diagnostic;
      Bad_UTF8   : constant Byte_Array (5 .. 6) := [16#C2#, 16#20#];
   begin
      declare
         Zero : Flyology_CBOR.Bounded_Writing.Writer (0, 1);
      begin
         Flyology_CBOR.Bounded_Writing.Initialize (Zero, Writer_Profile, Diagnostic);
         Flyology_CBOR.Bounded_Writing.Begin_Document (Zero, Diagnostic);
         Flyology_CBOR.Bounded_Writing.Put_Null (Zero, Diagnostic);
         Check
           (Diagnostic.Code = Flyology_CBOR.Errors.Destination_Exhausted,
            "zero-capacity exhaustion");
         Check (Flyology_CBOR.Bounded_Writing.Staged_Length (Zero) = 0, "zero staged prefix");
      end;

      declare
         Shallow : Flyology_CBOR.Bounded_Writing.Writer (8, 0);
      begin
         Flyology_CBOR.Bounded_Writing.Initialize (Shallow, Writer_Profile, Diagnostic);
         Flyology_CBOR.Bounded_Writing.Begin_Document (Shallow, Diagnostic);
         Flyology_CBOR.Bounded_Writing.Begin_Array (Shallow, 0, Diagnostic);
         Check (Diagnostic.Code = Flyology_CBOR.Errors.Depth_Exhausted, "writer depth bound");
         Check (Flyology_CBOR.Bounded_Writing.Staged_Length (Shallow) = 0, "depth before write");
      end;

      declare
         Text : Flyology_CBOR.Bounded_Writing.Writer (16, 1);
      begin
         Flyology_CBOR.Bounded_Writing.Initialize (Text, Writer_Profile, Diagnostic);
         Flyology_CBOR.Bounded_Writing.Begin_Document (Text, Diagnostic);
         Flyology_CBOR.Bounded_Writing.Begin_Text_String (Text, 2, Diagnostic);
         Flyology_CBOR.Bounded_Writing.Put_Text_String_Fragment (Text, Bad_UTF8, Diagnostic);
         Check (Diagnostic.Code = Flyology_CBOR.Errors.Invalid_UTF8, "writer UTF-8 failure");
         Check
           (Diagnostic.Coordinate = Flyology_CBOR.Errors.Writer_Token_Byte
            and then Diagnostic.Offset = 1,
            "writer UTF-8 coordinate");
         Check (Flyology_CBOR.Bounded_Writing.Staged_Length (Text) = 1, "UTF-8 head retained");
      end;

      declare
         Map : Flyology_CBOR.Bounded_Writing.Writer (16, 2);
      begin
         Flyology_CBOR.Bounded_Writing.Initialize (Map, Writer_Profile, Diagnostic);
         Flyology_CBOR.Bounded_Writing.Begin_Document (Map, Diagnostic);
         Flyology_CBOR.Bounded_Writing.Begin_Map (Map, 1, Diagnostic);
         Flyology_CBOR.Bounded_Writing.Put_Unsigned (Map, 1, Diagnostic);
         Flyology_CBOR.Bounded_Writing.End_Map (Map, Diagnostic);
         Check
           (Diagnostic.Code = Flyology_CBOR.Errors.Invalid_Writer_Grammar,
            "writer rejects incomplete map pair");
      end;

      declare
         Complete : Flyology_CBOR.Bounded_Writing.Writer (8, 1);
         Small    : Byte_Array (3 .. 3) := [others => 16#AA#];
         Produced : Ada.Streams.Stream_Element_Count;
      begin
         Flyology_CBOR.Bounded_Writing.Initialize (Complete, Writer_Profile, Diagnostic);
         Flyology_CBOR.Bounded_Writing.Begin_Document (Complete, Diagnostic);
         Flyology_CBOR.Bounded_Writing.Put_Unsigned (Complete, 1_000, Diagnostic);
         Flyology_CBOR.Bounded_Writing.Finish_Document (Complete, Diagnostic);
         Flyology_CBOR.Bounded_Writing.Copy_Output
           (Complete, Small, Produced, Diagnostic);
         Check
           (Diagnostic.Code = Flyology_CBOR.Errors.Destination_Exhausted and then Produced = 0,
            "copy rejects insufficient target");
         Check (Small (3) = 16#AA#, "failed copy leaves target unchanged");
      end;
   end Test_Writer_Failures;

   procedure Test_Allocating_Writer is
      Writer     : Flyology_CBOR.Allocating_Writing.Writer (2);
      Diagnostic : Flyology_CBOR.Errors.Diagnostic;
   begin
      Flyology_CBOR.Allocating_Writing.Initialize (Writer, Writer_Profile, Diagnostic);
      Flyology_CBOR.Allocating_Writing.Begin_Document (Writer, Diagnostic);
      Flyology_CBOR.Allocating_Writing.Put_Negative_Argument
        (Writer, Interfaces.Unsigned_64'Last, Diagnostic);
      Flyology_CBOR.Allocating_Writing.Finish_Document (Writer, Diagnostic);
      Check_Clear (Diagnostic, "allocating finish");
      Check
        (Flyology_CBOR.Allocating_Writing.Committed_Length (Writer) = 9,
         "allocating length");
      declare
         Output : constant Byte_Array := Flyology_CBOR.Allocating_Writing.Output (Writer);
      begin
         Check (Output'First = 1 and then Output'Length = 9, "allocating output bounds");
         Check (Output (1) = 16#3B# and then Output (9) = 16#FF#, "allocating output bytes");
      end;
   end Test_Allocating_Writer;

   procedure Test_External_Writer_Transactions is
      Writer     : External_Writing.Writer (2);
      Target     : External_Destination;
      Diagnostic : Flyology_CBOR.Errors.Diagnostic;
   begin
      External_Writing.Initialize (Writer, Writer_Profile, Diagnostic);
      External_Writing.Begin_Document (Writer, Target, Diagnostic);
      External_Writing.Put_Unsigned (Writer, Target, 24, Diagnostic);
      Check (not Target.Published, "external writes remain unpublished");
      External_Writing.Finish_Document (Writer, Target, Diagnostic);
      Check_Clear (Diagnostic, "external commit");
      Check (Target.Published, "external commit publishes");

      External_Writing.Reset (Writer, Writer_Profile, Diagnostic);
      Target.Fail_Commit := True;
      Target.Fail_Abort := True;
      External_Writing.Begin_Document (Writer, Target, Diagnostic);
      External_Writing.Put_Unsigned (Writer, Target, 1, Diagnostic);
      External_Writing.Finish_Document (Writer, Target, Diagnostic);
      Check (Diagnostic.Code = Flyology_CBOR.Errors.Commit_Failed, "commit primary");
      Check
        (Diagnostic.Secondary = Flyology_CBOR.Errors.Abort_Failed,
         "abort failure remains secondary");
      Check (not Target.Published, "failed commit never publishes");
   end Test_External_Writer_Transactions;

begin
   Test_Values_And_Numbers;
   Test_Parser_Transcript;
   Test_Parser_Failures_And_Drain;
   Test_All_Initial_Octets;
   Test_Bounded_Writer;
   Test_Writer_Lifecycle;
   Test_Writer_Failures;
   Test_Allocating_Writer;
   Test_External_Writer_Transactions;
   Ada.Text_IO.Put_Line ("flyology_cbor tests: PASS");
end Flyology_CBOR_Tests;
