with Ada.Streams;
with Ada.Text_IO;
with Flyology_CBOR.Allocating_Writing;
with Flyology_CBOR.Allocating_Writing.Test_Support;
with Flyology_CBOR.Bounded_Writing;
with Flyology_CBOR.Destinations;
with Flyology_CBOR.Errors;
with Flyology_CBOR.Numbers.Binary64;
with Flyology_CBOR.Numbers.Signed_Integers;
with Flyology_CBOR.Numbers.Unsigned_Integers;
with Flyology_CBOR.Parsing;
with Flyology_CBOR.Parsing.Test_Support;
with Flyology_CBOR.Profiles;
with Flyology_CBOR.Values;
with Flyology_CBOR.Writing;
with Interfaces;

procedure Flyology_CBOR_Tests is
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Streams.Stream_Element_Count;
   use type Flyology_CBOR.Allocating_Writing.Writer_State;
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
   use type Flyology_CBOR.Parsing.Source_Range;
   use type Flyology_CBOR.Values.Float_Category;
   use type Flyology_CBOR.Values.Float_Construction_Status;
   use type Flyology_CBOR.Values.Float_Width;
   use type Flyology_CBOR.Values.Integer_Kind;
   use type Flyology_CBOR.Values.Length_Kind;
   use type Interfaces.Integer_64;
   use type Interfaces.Integer_128;
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   subtype Byte_Array is Ada.Streams.Stream_Element_Array;
   subtype Offset is Ada.Streams.Stream_Element_Offset;
   type Event_Kind_Array is
     array (Positive range <>) of Flyology_CBOR.Parsing.Event_Kind;

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
      Fail_Begin  : Boolean := False;
      Fail_Write  : Boolean := False;
      Raise_Write : Boolean := False;
      Write_Limit : Ada.Streams.Stream_Element_Count := 32;
      Fail_Commit : Boolean := False;
      Fail_Abort  : Boolean := False;
   end record;

   procedure External_Begin
     (Target : in out External_Destination;
      Status : out Flyology_CBOR.Destinations.Begin_Status)
   is
   begin
      if Target.Fail_Begin or else Target.Begun then
         Status := Flyology_CBOR.Destinations.Begin_Failed;
         return;
      end if;
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
      if Target.Raise_Write then
         raise Constraint_Error with "test destination contract violation";
      elsif Target.Fail_Write or else not Target.Begun then
         Written := 0;
         Status := Flyology_CBOR.Destinations.Write_Failed;
         return;
      elsif Ada.Streams.Stream_Element_Count (Data'Length) > Target.Write_Limit then
         Written := Target.Write_Limit;
         for Count in 0 .. Written - 1 loop
            Target.Length := Target.Length + 1;
            Target.Buffer (Offset (Target.Length)) := Data (Data'First + Offset (Count));
         end loop;
         Status := Flyology_CBOR.Destinations.Write_Exhausted;
         return;
      elsif not Target.Begun
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

   use type External_Writing.Writer_State;

   procedure Test_Values_And_Numbers is
      type Tiny_Signed is range -8 .. 7;
      type Tiny_Unsigned is mod 16;

      package Signed_64_Conversions is new
        Flyology_CBOR.Numbers.Signed_Integers (Interfaces.Integer_64);
      package Unsigned_64_Conversions is new
        Flyology_CBOR.Numbers.Unsigned_Integers (Interfaces.Unsigned_64);
      package Signed_128_Conversions is new
        Flyology_CBOR.Numbers.Signed_Integers (Interfaces.Integer_128);
      package Tiny_Signed_Conversions is new
        Flyology_CBOR.Numbers.Signed_Integers (Tiny_Signed);
      package Tiny_Unsigned_Conversions is new
        Flyology_CBOR.Numbers.Unsigned_Integers (Tiny_Unsigned);

      use type Signed_64_Conversions.Conversion_Status;
      use type Unsigned_64_Conversions.Conversion_Status;
      use type Signed_128_Conversions.Conversion_Status;
      use type Tiny_Signed_Conversions.Conversion_Status;
      use type Tiny_Unsigned_Conversions.Conversion_Status;

      Float_Item   : Flyology_CBOR.Values.Float_Value;
      Float_Status : Flyology_CBOR.Values.Float_Construction_Status;
      Binary       : Flyology_CBOR.Numbers.Binary64.Conversion_Result;
      Signed       : Signed_64_Conversions.Conversion_Result;
      Unsigned     : Unsigned_64_Conversions.Conversion_Result;
      Signed_128   : Signed_128_Conversions.Conversion_Result;
      Tiny_Integer : Tiny_Signed_Conversions.Conversion_Result;
      Tiny_Natural : Tiny_Unsigned_Conversions.Conversion_Result;
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
      Unsigned_64_Conversions.Convert
        (Flyology_CBOR.Values.Unsigned (Interfaces.Unsigned_64'Last), Unsigned);
      Check
        (Unsigned_64_Conversions.Status (Unsigned) = Unsigned_64_Conversions.Converted
         and then Unsigned_64_Conversions.Value (Unsigned) = Interfaces.Unsigned_64'Last,
         "unsigned maximum converts exactly");
      Signed_64_Conversions.Convert
        (Flyology_CBOR.Values.Unsigned
           (Interfaces.Unsigned_64 (Interfaces.Integer_64'Last)),
         Signed);
      Check
        (Signed_64_Conversions.Status (Signed) = Signed_64_Conversions.Converted
         and then Signed_64_Conversions.Value (Signed) = Interfaces.Integer_64'Last,
         "signed positive maximum converts exactly");
      Signed_64_Conversions.Convert
        (Flyology_CBOR.Values.Unsigned
           (Interfaces.Unsigned_64 (Interfaces.Integer_64'Last) + 1),
         Signed);
      Check
        (Signed_64_Conversions.Status (Signed) = Signed_64_Conversions.Above_Range,
         "signed positive overflow is checked");
      Signed_128_Conversions.Convert
        (Flyology_CBOR.Values.Unsigned (Interfaces.Unsigned_64'Last), Signed_128);
      Check
        (Signed_128_Conversions.Status (Signed_128) = Signed_128_Conversions.Converted,
         "unsigned U64 converts to signed 128");
      Check
        (Signed_128_Conversions.Value (Signed_128)
         = Interfaces.Integer_128 (Interfaces.Unsigned_64'Last),
         "signed 128 conversion value");
      Tiny_Signed_Conversions.Convert (Flyology_CBOR.Values.Negative (7), Tiny_Integer);
      Check
        (Tiny_Signed_Conversions.Status (Tiny_Integer) = Tiny_Signed_Conversions.Converted
         and then Tiny_Signed_Conversions.Value (Tiny_Integer) = -8,
         "narrow signed minimum converts");
      Tiny_Signed_Conversions.Convert (Flyology_CBOR.Values.Negative (8), Tiny_Integer);
      Check
        (Tiny_Signed_Conversions.Status (Tiny_Integer) = Tiny_Signed_Conversions.Below_Range,
         "narrow signed below range");
      Tiny_Signed_Conversions.Convert (Flyology_CBOR.Values.Unsigned (8), Tiny_Integer);
      Check
        (Tiny_Signed_Conversions.Status (Tiny_Integer) = Tiny_Signed_Conversions.Above_Range,
         "narrow signed above range");
      Tiny_Unsigned_Conversions.Convert (Flyology_CBOR.Values.Unsigned (15), Tiny_Natural);
      Check
        (Tiny_Unsigned_Conversions.Status (Tiny_Natural)
           = Tiny_Unsigned_Conversions.Converted
         and then Tiny_Unsigned_Conversions.Value (Tiny_Natural) = 15,
         "narrow modular maximum converts");
      Tiny_Unsigned_Conversions.Convert (Flyology_CBOR.Values.Unsigned (16), Tiny_Natural);
      Check
        (Tiny_Unsigned_Conversions.Status (Tiny_Natural)
           = Tiny_Unsigned_Conversions.Above_Range,
         "narrow modular above range");

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
        (Flyology_CBOR.Values.Binary16, 16#8000#, Float_Item, Float_Status);
      Flyology_CBOR.Numbers.Binary64.Convert (Float_Item, Binary);
      Check
        (Flyology_CBOR.Numbers.Binary64.Value (Binary) = 16#8000_0000_0000_0000#,
         "binary16 negative zero promotes exactly");

      Flyology_CBOR.Values.Make_Float
        (Flyology_CBOR.Values.Binary32, 1, Float_Item, Float_Status);
      Flyology_CBOR.Numbers.Binary64.Convert (Float_Item, Binary);
      Check
        (Flyology_CBOR.Numbers.Binary64.Value (Binary) = 16#36A0_0000_0000_0000#,
         "binary32 minimum subnormal promotes exactly");

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
        (Flyology_CBOR.Values.Binary16, 16#FC00#, Float_Item, Float_Status);
      Flyology_CBOR.Numbers.Binary64.Convert (Float_Item, Binary);
      Check
        (Flyology_CBOR.Numbers.Binary64.Status (Binary)
           = Flyology_CBOR.Numbers.Binary64.Converted_Negative_Infinity,
         "negative infinity category conversion");

      Flyology_CBOR.Values.Make_Float
        (Flyology_CBOR.Values.Binary32, 16#7FC0_0001#, Float_Item, Float_Status);
      Flyology_CBOR.Numbers.Binary64.Convert (Float_Item, Binary);
      Check
        (Flyology_CBOR.Values.Category (Float_Item) = Flyology_CBOR.Values.Not_A_Number
         and then Flyology_CBOR.Numbers.Binary64.Status (Binary)
           = Flyology_CBOR.Numbers.Binary64.Converted_Not_A_Number,
         "NaN category conversion");

      Flyology_CBOR.Values.Make_Float
        (Flyology_CBOR.Values.Binary64, 16#BFF0_0000_0000_0000#, Float_Item, Float_Status);
      Flyology_CBOR.Numbers.Binary64.Convert (Float_Item, Binary);
      Check
        (Flyology_CBOR.Numbers.Binary64.Value (Binary) = 16#BFF0_0000_0000_0000#,
         "binary64 finite bits pass through exactly");

      Flyology_CBOR.Values.Make_Float
        (Flyology_CBOR.Values.Binary16, 16#1_0000#, Float_Item, Float_Status);
      Check
        (Float_Status = Flyology_CBOR.Values.Bits_Out_Of_Range,
         "float high bits rejected");
   end Test_Values_And_Numbers;

   procedure Test_Oracle_Scalars is
      Empty : constant Byte_Array (1 .. 0) := [];

      procedure Root_Event
        (Input : Byte_Array;
         Item  : out Flyology_CBOR.Parsing.Event)
      is
         Parser     : Flyology_CBOR.Parsing.Parser (4);
         Diagnostic : Flyology_CBOR.Errors.Diagnostic;
         Result     : Flyology_CBOR.Parsing.Step_Result;
         Consumed   : Ada.Streams.Stream_Element_Count := 0;
      begin
         Flyology_CBOR.Parsing.Initialize (Parser, Parser_Profile, Diagnostic);
         loop
            if Consumed < Ada.Streams.Stream_Element_Count (Input'Length) then
               Flyology_CBOR.Parsing.Step
                 (Parser,
                  Input
                    (Input'First + Offset (Consumed) .. Input'Last),
                  True,
                  Result);
            else
               Flyology_CBOR.Parsing.Step (Parser, Empty, True, Result);
            end if;
            Consumed := Consumed + Result.Consumed;
            if Result.Outcome = Flyology_CBOR.Parsing.Event_Ready
              and then Flyology_CBOR.Parsing.Kind (Result.Item)
                /= Flyology_CBOR.Parsing.Document_Begin
            then
               Item := Result.Item;
               return;
            end if;
            Check
              (Result.Outcome = Flyology_CBOR.Parsing.Event_Ready,
               "oracle scalar reaches semantic event");
         end loop;
      end Root_Event;

      procedure Check_Integer
        (Input    : Byte_Array;
         Kind     : Flyology_CBOR.Values.Integer_Kind;
         Argument : Interfaces.Unsigned_64)
      is
         Item   : Flyology_CBOR.Parsing.Event;
         Value  : Flyology_CBOR.Values.Integer_Value;
         Source : Flyology_CBOR.Parsing.Source_Range;
      begin
         Root_Event (Input, Item);
         Check
           (Flyology_CBOR.Parsing.Kind (Item)
              = (if Kind = Flyology_CBOR.Values.Unsigned_Integer
                 then Flyology_CBOR.Parsing.Unsigned_Value
                 else Flyology_CBOR.Parsing.Negative_Integer_Value),
            "oracle integer event kind");
         Value := Flyology_CBOR.Parsing.Integer_Data (Item);
         Source := Flyology_CBOR.Parsing.Source (Item);
         Check
           (Flyology_CBOR.Values.Kind (Value) = Kind
            and then Flyology_CBOR.Values.Integer_Argument (Value) = Argument,
            "oracle integer argument");
         Check
           (Source.First = 0
            and then Source.Octet_Length = Interfaces.Unsigned_64 (Input'Length),
            "oracle integer source");
      end Check_Integer;

      procedure Check_Float
        (Input : Byte_Array;
         Width : Flyology_CBOR.Values.Float_Width;
         Bits  : Interfaces.Unsigned_64)
      is
         Item  : Flyology_CBOR.Parsing.Event;
         Value : Flyology_CBOR.Values.Float_Value;
      begin
         Root_Event (Input, Item);
         Check
           (Flyology_CBOR.Parsing.Kind (Item) = Flyology_CBOR.Parsing.Float_Value,
            "oracle float event kind");
         Value := Flyology_CBOR.Parsing.Float_Data (Item);
         Check
           (Flyology_CBOR.Values.Width (Value) = Width
            and then Flyology_CBOR.Values.Bits (Value) = Bits,
            "oracle raw float width and bits");
      end Check_Float;

      Item : Flyology_CBOR.Parsing.Event;
   begin
      Check_Integer
        ([16#18#, 16#18#], Flyology_CBOR.Values.Unsigned_Integer, 24);
      Check_Integer
        ([16#18#, 16#FF#], Flyology_CBOR.Values.Unsigned_Integer, 255);
      Check_Integer
        ([16#19#, 1, 0], Flyology_CBOR.Values.Unsigned_Integer, 256);
      Check_Integer
        ([16#19#, 16#FF#, 16#FF#], Flyology_CBOR.Values.Unsigned_Integer, 65_535);
      Check_Integer
        ([16#1A#, 0, 1, 0, 0], Flyology_CBOR.Values.Unsigned_Integer, 65_536);
      Check_Integer
        ([16#1B#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#],
         Flyology_CBOR.Values.Unsigned_Integer,
         Interfaces.Unsigned_64'Last);
      Check_Integer
        ([16#38#, 16#18#], Flyology_CBOR.Values.Negative_Integer, 24);
      Check_Integer
        ([16#3B#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#],
         Flyology_CBOR.Values.Negative_Integer,
         Interfaces.Unsigned_64'Last);

      Check_Float ([16#F9#, 16#80#, 0], Flyology_CBOR.Values.Binary16, 16#8000#);
      Check_Float
        ([16#FA#, 16#7F#, 16#C0#, 0, 1], Flyology_CBOR.Values.Binary32, 16#7FC0_0001#);
      Check_Float
        ([16#FB#, 16#BF#, 16#F0#, 0, 0, 0, 0, 0, 0],
         Flyology_CBOR.Values.Binary64,
         16#BFF0_0000_0000_0000#);

      Root_Event ([16#F8#, 16#20#], Item);
      Check
        (Flyology_CBOR.Parsing.Kind (Item) = Flyology_CBOR.Parsing.Simple_Value
         and then Flyology_CBOR.Parsing.Simple_Data (Item) = 32,
         "oracle raw simple value");
      Root_Event ([16#F4#], Item);
      Check
        (Flyology_CBOR.Parsing.Kind (Item) = Flyology_CBOR.Parsing.False_Value,
         "oracle false value");
      Root_Event ([16#F5#], Item);
      Check
        (Flyology_CBOR.Parsing.Kind (Item) = Flyology_CBOR.Parsing.True_Value,
         "oracle true value");
      Root_Event ([16#F6#], Item);
      Check
        (Flyology_CBOR.Parsing.Kind (Item) = Flyology_CBOR.Parsing.Null_Value,
         "oracle null value");
      Root_Event ([16#F7#], Item);
      Check
        (Flyology_CBOR.Parsing.Kind (Item) = Flyology_CBOR.Parsing.Undefined_Value,
         "oracle undefined value");
   end Test_Oracle_Scalars;

   procedure Test_Oracle_Structures_And_Strings is
      Empty : constant Byte_Array (1 .. 0) := [];

      procedure First_Event
        (Input : Byte_Array;
         Item  : out Flyology_CBOR.Parsing.Event)
      is
         Parser     : Flyology_CBOR.Parsing.Parser (4);
         Diagnostic : Flyology_CBOR.Errors.Diagnostic;
         Result     : Flyology_CBOR.Parsing.Step_Result;
         Consumed   : Ada.Streams.Stream_Element_Count := 0;
      begin
         Flyology_CBOR.Parsing.Initialize (Parser, Parser_Profile, Diagnostic);
         loop
            Flyology_CBOR.Parsing.Step
              (Parser,
               (if Consumed = Ada.Streams.Stream_Element_Count (Input'Length)
                then Empty
                else Input (Input'First + Offset (Consumed) .. Input'Last)),
               True,
               Result);
            Consumed := Consumed + Result.Consumed;
            if Result.Outcome = Flyology_CBOR.Parsing.Event_Ready
              and then Flyology_CBOR.Parsing.Kind (Result.Item)
                /= Flyology_CBOR.Parsing.Document_Begin
            then
               Item := Result.Item;
               return;
            end if;
            Check
              (Result.Outcome = Flyology_CBOR.Parsing.Event_Ready,
               "first structural event");
         end loop;
      end First_Event;

      procedure Check_Transcript
        (Input    : Byte_Array;
         Expected : Event_Kind_Array;
         Context  : String)
      is
         Parser     : Flyology_CBOR.Parsing.Parser (12);
         Diagnostic : Flyology_CBOR.Errors.Diagnostic;
         Result     : Flyology_CBOR.Parsing.Step_Result;
         Consumed   : Ada.Streams.Stream_Element_Count := 0;
         Seen       : Natural := 0;
      begin
         Flyology_CBOR.Parsing.Initialize (Parser, Parser_Profile, Diagnostic);
         loop
            if Consumed < Ada.Streams.Stream_Element_Count (Input'Length) then
               Flyology_CBOR.Parsing.Step
                 (Parser,
                  Input (Input'First + Offset (Consumed) .. Input'Last),
                  True,
                  Result);
            else
               Flyology_CBOR.Parsing.Step (Parser, Empty, True, Result);
            end if;
            Consumed := Consumed + Result.Consumed;
            exit when Result.Outcome = Flyology_CBOR.Parsing.Document_Complete;
            Check
              (Result.Outcome = Flyology_CBOR.Parsing.Event_Ready,
               Context & " transcript outcome");
            Seen := Seen + 1;
            Check (Seen <= Expected'Length, Context & " transcript overflow");
            Check
              (Flyology_CBOR.Parsing.Kind (Result.Item) = Expected (Seen),
               Context & " transcript event" & Natural'Image (Seen));
         end loop;
         Check (Seen = Expected'Length, Context & " transcript length");
         Check
           (Consumed = Ada.Streams.Stream_Element_Count (Input'Length),
            Context & " transcript consumed length");
      end Check_Transcript;

      Item : Flyology_CBOR.Parsing.Event;
   begin
      Check_Transcript
        ([16#5F#, 16#42#, 0, 1, 16#40#, 16#41#, 2, 16#FF#],
         [Flyology_CBOR.Parsing.Document_Begin,
          Flyology_CBOR.Parsing.Byte_String_Begin,
          Flyology_CBOR.Parsing.Byte_String_Chunk_Begin,
          Flyology_CBOR.Parsing.Byte_String_Fragment,
          Flyology_CBOR.Parsing.Byte_String_Chunk_End,
          Flyology_CBOR.Parsing.Byte_String_Chunk_Begin,
          Flyology_CBOR.Parsing.Byte_String_Chunk_End,
          Flyology_CBOR.Parsing.Byte_String_Chunk_Begin,
          Flyology_CBOR.Parsing.Byte_String_Fragment,
          Flyology_CBOR.Parsing.Byte_String_Chunk_End,
          Flyology_CBOR.Parsing.Byte_String_End,
          Flyology_CBOR.Parsing.Document_End],
         "indefinite byte string");
      Check_Transcript
        ([16#7F#, 16#62#, 16#C3#, 16#A9#, 16#60#, 16#61#, 16#78#, 16#FF#],
         [Flyology_CBOR.Parsing.Document_Begin,
          Flyology_CBOR.Parsing.Text_String_Begin,
          Flyology_CBOR.Parsing.Text_String_Chunk_Begin,
          Flyology_CBOR.Parsing.Text_String_Fragment,
          Flyology_CBOR.Parsing.Text_String_Chunk_End,
          Flyology_CBOR.Parsing.Text_String_Chunk_Begin,
          Flyology_CBOR.Parsing.Text_String_Chunk_End,
          Flyology_CBOR.Parsing.Text_String_Chunk_Begin,
          Flyology_CBOR.Parsing.Text_String_Fragment,
          Flyology_CBOR.Parsing.Text_String_Chunk_End,
          Flyology_CBOR.Parsing.Text_String_End,
         Flyology_CBOR.Parsing.Document_End],
         "indefinite text string");
      Check_Transcript
        ([16#62#, 16#C3#, 16#A9#],
         [Flyology_CBOR.Parsing.Document_Begin,
          Flyology_CBOR.Parsing.Text_String_Begin,
          Flyology_CBOR.Parsing.Text_String_Fragment,
          Flyology_CBOR.Parsing.Text_String_End,
          Flyology_CBOR.Parsing.Document_End],
         "definite text string");
      Check_Transcript
        ([16#82#, 16#40#, 16#60#],
         [Flyology_CBOR.Parsing.Document_Begin,
          Flyology_CBOR.Parsing.Array_Begin,
          Flyology_CBOR.Parsing.Byte_String_Begin,
          Flyology_CBOR.Parsing.Byte_String_End,
          Flyology_CBOR.Parsing.Text_String_Begin,
          Flyology_CBOR.Parsing.Text_String_End,
          Flyology_CBOR.Parsing.Array_End,
          Flyology_CBOR.Parsing.Document_End],
         "empty definite strings");
      Check_Transcript
        ([16#82#, 16#A1#, 1, 2, 16#9F#, 16#C0#, 16#F6#, 16#FF#],
         [Flyology_CBOR.Parsing.Document_Begin,
          Flyology_CBOR.Parsing.Array_Begin,
          Flyology_CBOR.Parsing.Map_Begin,
          Flyology_CBOR.Parsing.Unsigned_Value,
          Flyology_CBOR.Parsing.Unsigned_Value,
          Flyology_CBOR.Parsing.Map_End,
          Flyology_CBOR.Parsing.Array_Begin,
          Flyology_CBOR.Parsing.Tag_Begin,
          Flyology_CBOR.Parsing.Null_Value,
          Flyology_CBOR.Parsing.Tag_End,
          Flyology_CBOR.Parsing.Array_End,
          Flyology_CBOR.Parsing.Array_End,
          Flyology_CBOR.Parsing.Document_End],
         "nested containers and tag");
      Check_Transcript
        ([16#C0#, 16#C0#, 16#F6#],
         [Flyology_CBOR.Parsing.Document_Begin,
          Flyology_CBOR.Parsing.Tag_Begin,
          Flyology_CBOR.Parsing.Tag_Begin,
          Flyology_CBOR.Parsing.Null_Value,
          Flyology_CBOR.Parsing.Tag_End,
          Flyology_CBOR.Parsing.Tag_End,
          Flyology_CBOR.Parsing.Document_End],
         "stacked tags");

      First_Event ([16#D9#, 16#D9#, 16#F7#, 16#F6#], Item);
      Check
        (Flyology_CBOR.Parsing.Kind (Item) = Flyology_CBOR.Parsing.Tag_Begin
         and then Flyology_CBOR.Parsing.Tag_Data (Item) = 55_799,
         "self-described tag remains raw syntax");
      First_Event
        ([16#5B#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#], Item);
      Check
        (Flyology_CBOR.Parsing.Kind (Item) = Flyology_CBOR.Parsing.Byte_String_Begin
         and then Flyology_CBOR.Values.Length
           (Flyology_CBOR.Parsing.Declared_Length (Item)) = Interfaces.Unsigned_64'Last,
         "64-bit string length stays neutral");
   end Test_Oracle_Structures_And_Strings;

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

   procedure Test_Split_Head_Provenance is
      Empty : constant Byte_Array (1 .. 0) := [];

      procedure Check_Head (Input : Byte_Array) is
      begin
         for Split in 1 .. Input'Length - 1 loop
            declare
               Parser     : Flyology_CBOR.Parsing.Parser (4);
               Diagnostic : Flyology_CBOR.Errors.Diagnostic;
               Result     : Flyology_CBOR.Parsing.Step_Result;
               Cut        : constant Offset := Input'First + Offset (Split) - 1;
               Event_Source : Flyology_CBOR.Parsing.Source_Range;
            begin
               Flyology_CBOR.Parsing.Initialize (Parser, Parser_Profile, Diagnostic);
               Flyology_CBOR.Parsing.Step (Parser, Empty, False, Result);
               Check
                 (Result.Outcome = Flyology_CBOR.Parsing.Event_Ready
                  and then Flyology_CBOR.Parsing.Kind (Result.Item)
                    = Flyology_CBOR.Parsing.Document_Begin,
                  "split head document begin");

               Flyology_CBOR.Parsing.Step
                 (Parser, Input (Input'First .. Cut), False, Result);
               Check
                 (Result.Outcome = Flyology_CBOR.Parsing.Need_Input,
                  "split head prefix needs input");
               Check
                 (Result.Consumed = Ada.Streams.Stream_Element_Count (Split),
                  "split head prefix consumed");

               Flyology_CBOR.Parsing.Step
                 (Parser, Input (Cut + 1 .. Input'Last), True, Result);
               Check
                 (Result.Outcome = Flyology_CBOR.Parsing.Event_Ready
                  and then Flyology_CBOR.Parsing.Kind (Result.Item)
                    = Flyology_CBOR.Parsing.Unsigned_Value,
                  "split head produces unsigned event");
               Event_Source := Flyology_CBOR.Parsing.Source (Result.Item);
               Check
                 (Event_Source.First = 0
                  and then Event_Source.Octet_Length
                    = Interfaces.Unsigned_64 (Input'Length),
                  "split head retains complete source range");
               Check
                 (not Flyology_CBOR.Parsing.Has_Raw_Slice (Result.Item),
                  "split head has no borrowed raw slice");
            end;
         end loop;
      end Check_Head;

      procedure Check_Invalid_Simple is
         Input      : constant Byte_Array (51 .. 52) := [16#F8#, 16#1F#];
         Parser     : Flyology_CBOR.Parsing.Parser (2);
         Diagnostic : Flyology_CBOR.Errors.Diagnostic;
         Result     : Flyology_CBOR.Parsing.Step_Result;
      begin
         Flyology_CBOR.Parsing.Initialize (Parser, Parser_Profile, Diagnostic);
         Flyology_CBOR.Parsing.Step (Parser, Empty, False, Result);
         Flyology_CBOR.Parsing.Step (Parser, Input (51 .. 51), False, Result);
         Check
           (Result.Outcome = Flyology_CBOR.Parsing.Need_Input,
            "split invalid simple prefix");
         Flyology_CBOR.Parsing.Step (Parser, Input (52 .. 52), True, Result);
         Check
           (Result.Outcome = Flyology_CBOR.Parsing.Step_Failed
            and then Result.Diagnostic.Code = Flyology_CBOR.Errors.Invalid_Simple_Value
            and then Result.Diagnostic.Offset = 0
            and then Result.Diagnostic.Construct_Offset = 0,
            "split invalid simple anchor");
      end Check_Invalid_Simple;

      procedure Check_Invalid_String_Chunk is
         Input : constant Byte_Array (61 .. 64) := [16#5F#, 16#79#, 0, 0];
      begin
         for Split in 1 .. 2 loop
            declare
               Parser     : Flyology_CBOR.Parsing.Parser (2);
               Diagnostic : Flyology_CBOR.Errors.Diagnostic;
               Result     : Flyology_CBOR.Parsing.Step_Result;
               Cut        : constant Offset := 61 + Offset (Split);
            begin
               Flyology_CBOR.Parsing.Initialize (Parser, Parser_Profile, Diagnostic);
               Flyology_CBOR.Parsing.Step (Parser, Empty, False, Result);
               Flyology_CBOR.Parsing.Step (Parser, Input (61 .. 61), False, Result);
               Check
                 (Result.Outcome = Flyology_CBOR.Parsing.Event_Ready,
                  "indefinite byte string begin");
               Flyology_CBOR.Parsing.Step (Parser, Input (62 .. Cut), False, Result);
               Check
                 (Result.Outcome = Flyology_CBOR.Parsing.Need_Input,
                  "split wrong string chunk prefix");
               Flyology_CBOR.Parsing.Step (Parser, Input (Cut + 1 .. 64), True, Result);
               Check
                 (Result.Outcome = Flyology_CBOR.Parsing.Step_Failed
                  and then Result.Diagnostic.Code = Flyology_CBOR.Errors.Invalid_String_Chunk
                  and then Result.Diagnostic.Offset = 1
                  and then Result.Diagnostic.Construct_Offset = 1,
                  "split wrong string chunk anchor");
            end;
         end loop;
      end Check_Invalid_String_Chunk;
   begin
      Check_Head ([41 => 16#18#, 42 => 16#18#]);
      Check_Head ([41 => 16#19#, 42 => 1, 43 => 0]);
      Check_Head ([41 => 16#1A#, 42 => 0, 43 => 1, 44 => 0, 45 => 0]);
      Check_Head
        ([41 => 16#1B#, 42 => 0, 43 => 0, 44 => 0, 45 => 0,
          46 => 0, 47 => 0, 48 => 0, 49 => 1]);
      Check_Invalid_Simple;
      Check_Invalid_String_Chunk;
   end Test_Split_Head_Provenance;

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
      Expect_Parser_Error ([16#1D#], Flyology_CBOR.Errors.Reserved_Additional_Information, 0, 0);
      Expect_Parser_Error ([16#1E#], Flyology_CBOR.Errors.Reserved_Additional_Information, 0, 0);
      Expect_Parser_Error ([16#1F#], Flyology_CBOR.Errors.Invalid_Indefinite_Item, 0, 0);
      Expect_Parser_Error ([16#FF#], Flyology_CBOR.Errors.Unexpected_Break, 0, 0);
      Expect_Parser_Error ([16#BF#, 1, 16#FF#], Flyology_CBOR.Errors.Odd_Map, 2, 2);
      Expect_Parser_Error ([16#C1#], Flyology_CBOR.Errors.Truncated_Input, 1, 1);
      Expect_Parser_Error ([16#82#, 1], Flyology_CBOR.Errors.Truncated_Input, 2, 2);
      Expect_Parser_Error ([16#A1#, 1], Flyology_CBOR.Errors.Truncated_Input, 2, 2);
      Expect_Parser_Error ([16#5F#, 16#60#], Flyology_CBOR.Errors.Invalid_String_Chunk, 1, 1);
      Expect_Parser_Error ([16#62#, 16#C2#, 16#20#], Flyology_CBOR.Errors.Invalid_UTF8, 2, 2);
      Expect_Parser_Error ([16#61#, 16#80#], Flyology_CBOR.Errors.Invalid_UTF8, 1, 1);
      Expect_Parser_Error ([16#61#, 16#C0#], Flyology_CBOR.Errors.Invalid_UTF8, 1, 1);
      Expect_Parser_Error ([16#61#, 16#C2#], Flyology_CBOR.Errors.Invalid_UTF8, 2, 1);
      Expect_Parser_Error
        ([16#63#, 16#E0#, 16#9F#, 16#80#], Flyology_CBOR.Errors.Invalid_UTF8, 2, 2);
      Expect_Parser_Error
        ([16#63#, 16#ED#, 16#A0#, 16#80#], Flyology_CBOR.Errors.Invalid_UTF8, 2, 2);
      Expect_Parser_Error
        ([16#64#, 16#F0#, 16#8F#, 16#80#, 16#80#], Flyology_CBOR.Errors.Invalid_UTF8, 2, 2);
      Expect_Parser_Error
        ([16#64#, 16#F4#, 16#90#, 16#80#, 16#80#], Flyology_CBOR.Errors.Invalid_UTF8, 2, 2);
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

      declare
         Shallow      : Flyology_CBOR.Parsing.Parser (1);
         Shallow_Step : Flyology_CBOR.Parsing.Step_Result;
         Nested       : constant Byte_Array (71 .. 72) := [16#81#, 16#80#];
      begin
         Flyology_CBOR.Parsing.Initialize (Shallow, Parser_Profile, Diagnostic);
         Flyology_CBOR.Parsing.Step (Shallow, Empty, False, Shallow_Step);
         Flyology_CBOR.Parsing.Step (Shallow, Nested, True, Shallow_Step);
         Flyology_CBOR.Parsing.Step (Shallow, Nested (72 .. 72), True, Shallow_Step);
         Check
           (Shallow_Step.Outcome = Flyology_CBOR.Parsing.Step_Failed
            and then Shallow_Step.Diagnostic.Code = Flyology_CBOR.Errors.Depth_Exhausted
            and then Shallow_Step.Diagnostic.Offset = 1,
            "parser syntax depth fails at denied opener");
      end;

      declare
         Exhausted : Flyology_CBOR.Parsing.Parser (1);
         Item      : Flyology_CBOR.Parsing.Step_Result;
         One       : constant Byte_Array (91 .. 91) := [0];
      begin
         Flyology_CBOR.Parsing.Initialize (Exhausted, Parser_Profile, Diagnostic);
         Flyology_CBOR.Parsing.Step (Exhausted, Empty, False, Item);
         Flyology_CBOR.Parsing.Test_Support.Set_Current_Offset
           (Exhausted, Flyology_CBOR.Parsing.Byte_Offset'Last);
         Flyology_CBOR.Parsing.Step (Exhausted, One, True, Item);
         Check
           (Item.Outcome = Flyology_CBOR.Parsing.Step_Failed
            and then Item.Consumed = 0
            and then Item.Diagnostic.Code = Flyology_CBOR.Errors.Offset_Exhausted
            and then Item.Diagnostic.Offset = Flyology_CBOR.Parsing.Byte_Offset'Last,
            "parser offset exhaustion is exact and nonconsuming");
      end;

      declare
         Deep         : Flyology_CBOR.Parsing.Parser (64);
         Deep_Step    : Flyology_CBOR.Parsing.Step_Result;
         Tag_Chain    : Byte_Array (1 .. 66) := [others => 16#C0#];
         Deep_Consumed : Ada.Streams.Stream_Element_Count := 0;
         Calls        : Natural := 0;
      begin
         Tag_Chain (66) := 16#F6#;
         Flyology_CBOR.Parsing.Initialize (Deep, Parser_Profile, Diagnostic);
         loop
            Calls := Calls + 1;
            Flyology_CBOR.Parsing.Step
              (Deep,
               Tag_Chain (Tag_Chain'First + Offset (Deep_Consumed) .. Tag_Chain'Last),
               True,
               Deep_Step);
            Deep_Consumed := Deep_Consumed + Deep_Step.Consumed;
            exit when Deep_Step.Outcome = Flyology_CBOR.Parsing.Step_Failed;
            Check
              (Deep_Step.Outcome = Flyology_CBOR.Parsing.Event_Ready,
               "hostile tag chain progress");
            Check (Calls <= 66, "hostile tag chain work bound");
         end loop;
         Check
           (Deep_Step.Diagnostic.Code = Flyology_CBOR.Errors.Depth_Exhausted
            and then Deep_Step.Diagnostic.Offset = 64
            and then Deep_Consumed = 65
            and then Flyology_CBOR.Parsing.Test_Support.Inspections (Deep) = 65,
            "hostile tag chain exact depth denial");
      end;

      for Opener of Byte_Array'(1 => 16#81#, 2 => 16#A1#) loop
         declare
            Deep      : Flyology_CBOR.Parsing.Parser (64);
            Item      : Flyology_CBOR.Parsing.Step_Result;
            Chain     : constant Byte_Array (1 .. 65) := [others => Opener];
            Consumed  : Ada.Streams.Stream_Element_Count := 0;
         begin
            Flyology_CBOR.Parsing.Initialize (Deep, Parser_Profile, Diagnostic);
            Flyology_CBOR.Parsing.Step (Deep, Empty, False, Item);
            loop
               Flyology_CBOR.Parsing.Step
                 (Deep, Chain (Chain'First + Offset (Consumed) .. Chain'Last), True, Item);
               Consumed := Consumed + Item.Consumed;
               exit when Item.Outcome = Flyology_CBOR.Parsing.Step_Failed;
            end loop;
            Check
              (Item.Diagnostic.Code = Flyology_CBOR.Errors.Depth_Exhausted
               and then Consumed = 65
               and then Flyology_CBOR.Parsing.Test_Support.Inspections (Deep) = 65,
               "maximum-depth array/map chain has exact linear work");
         end;
      end loop;

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

   procedure Test_Drain_Pending_Failure is
      Bad_Input  : constant Byte_Array (81 .. 81) := [16#1C#];
      True_Input : constant Byte_Array (91 .. 91) := [16#F5#];
      Empty      : constant Byte_Array (1 .. 0) := [];
      Seed       : Flyology_CBOR.Parsing.Parser (1);
      Parser     : Flyology_CBOR.Parsing.Parser (1);
      Aborter    : Flyology_CBOR.Parsing.Parser (1);
      Resetter   : Flyology_CBOR.Parsing.Parser (1);
      Diagnostic : Flyology_CBOR.Errors.Diagnostic;
      Step_Item  : Flyology_CBOR.Parsing.Step_Result;
      Result     : Flyology_CBOR.Parsing.Drain_Result;
      Events     : Flyology_CBOR.Parsing.Event_Array (31 .. 32);

      procedure Enter_Pending (Target : in out Flyology_CBOR.Parsing.Parser) is
      begin
         Flyology_CBOR.Parsing.Initialize (Target, Parser_Profile, Diagnostic);
         Events := [others => Step_Item.Item];
         Flyology_CBOR.Parsing.Drain
           (Target, Bad_Input, True, Events (31 .. 31), Result);
         Check
           (Result.Stop = Flyology_CBOR.Parsing.Output_Full
            and then Result.Produced = 1
            and then Result.Consumed = 1,
            "drain retains failure after full prefix");
         Check
           (Flyology_CBOR.Parsing.Kind (Events (31))
              = Flyology_CBOR.Parsing.Document_Begin
            and then Flyology_CBOR.Parsing.Kind (Events (32))
              = Flyology_CBOR.Parsing.True_Value,
            "drain mutates only eligible prefix");
         Check
           (Flyology_CBOR.Parsing.State (Target)
              = Flyology_CBOR.Parsing.Failure_Pending,
            "drain enters failure pending");
         Check
           (Flyology_CBOR.Parsing.Terminal_Diagnostic (Target).Code
              = Flyology_CBOR.Errors.Reserved_Additional_Information,
            "pending terminal diagnostic");
      end Enter_Pending;

      procedure Check_String_Pending
        (Input             : Byte_Array;
         Code              : Flyology_CBOR.Errors.Error_Code;
         Expected_Consumed : Ada.Streams.Stream_Element_Count;
         Context           : String)
      is
         Target : Flyology_CBOR.Parsing.Parser (2);
      begin
         Flyology_CBOR.Parsing.Initialize (Target, Parser_Profile, Diagnostic);
         Flyology_CBOR.Parsing.Drain (Target, Input, True, Events, Result);
         Check
           (Result.Stop = Flyology_CBOR.Parsing.Output_Full
            and then Result.Produced = 2
            and then Result.Consumed = Expected_Consumed
            and then Flyology_CBOR.Parsing.State (Target)
              = Flyology_CBOR.Parsing.Failure_Pending
            and then Flyology_CBOR.Parsing.Terminal_Diagnostic (Target).Code = Code,
            Context & " retained behind full output");
         Flyology_CBOR.Parsing.Drain (Target, Empty, True, Events, Result);
         Check
           (Result.Stop = Flyology_CBOR.Parsing.Drain_Failed
            and then Result.Consumed = 0
            and then Result.Produced = 0
            and then Result.Diagnostic.Code = Code,
            Context & " publishes with no new mutation");
      end Check_String_Pending;
   begin
      Flyology_CBOR.Parsing.Initialize (Seed, Parser_Profile, Diagnostic);
      Flyology_CBOR.Parsing.Step (Seed, Empty, False, Step_Item);
      Flyology_CBOR.Parsing.Step (Seed, True_Input, True, Step_Item);
      Check
        (Step_Item.Outcome = Flyology_CBOR.Parsing.Event_Ready
         and then Flyology_CBOR.Parsing.Kind (Step_Item.Item)
           = Flyology_CBOR.Parsing.True_Value,
         "seed suffix event");

      Enter_Pending (Parser);
      Flyology_CBOR.Parsing.Drain (Parser, Empty, True, Events, Result);
      Check
        (Result.Stop = Flyology_CBOR.Parsing.Drain_Failed
         and then Result.Consumed = 0
         and then Result.Produced = 0
         and then Result.Diagnostic.Code
           = Flyology_CBOR.Errors.Reserved_Additional_Information,
         "pending failure publishes without input or events");
      Check
        (Flyology_CBOR.Parsing.Kind (Events (31))
           = Flyology_CBOR.Parsing.Document_Begin
         and then Flyology_CBOR.Parsing.Kind (Events (32))
           = Flyology_CBOR.Parsing.True_Value,
         "pending failure preserves event array");
      Check
        (Flyology_CBOR.Parsing.State (Parser) = Flyology_CBOR.Parsing.Failed,
         "pending publication enters failed");
      Flyology_CBOR.Parsing.Reset (Parser, Parser_Profile, Diagnostic);
      Check_Clear (Diagnostic, "reset after pending publication");
      Check
        (Flyology_CBOR.Parsing.State (Parser) = Flyology_CBOR.Parsing.Ready,
         "reset returns parser to ready");

      Enter_Pending (Aborter);
      Flyology_CBOR.Parsing.Abort_Document (Aborter);
      Check
        (Flyology_CBOR.Parsing.State (Aborter) = Flyology_CBOR.Parsing.Failed
         and then Flyology_CBOR.Parsing.Terminal_Diagnostic (Aborter).Code
           = Flyology_CBOR.Errors.Reserved_Additional_Information,
         "abort promotes pending failure without replacing it");

      Enter_Pending (Resetter);
      Flyology_CBOR.Parsing.Reset (Resetter, Parser_Profile, Diagnostic);
      Check_Clear (Diagnostic, "reset directly from failure pending");
      Check
        (Flyology_CBOR.Parsing.State (Resetter) = Flyology_CBOR.Parsing.Ready,
         "direct pending reset returns parser to ready");

      Check_String_Pending
        ([16#61#, 16#80#], Flyology_CBOR.Errors.Invalid_UTF8, 2, "invalid text");
      Check_String_Pending
        ([16#61#, 16#C2#], Flyology_CBOR.Errors.Invalid_UTF8, 2, "incomplete text");
      Check_String_Pending
        ([16#62#, 16#61#], Flyology_CBOR.Errors.Truncated_Input, 1, "truncated text");
      Check_String_Pending
        ([16#42#, 16#01#], Flyology_CBOR.Errors.Truncated_Input, 1, "truncated bytes");

      declare
         Large_Bytes : Byte_Array (201 .. 4_299) := [others => 0];
         Large       : Flyology_CBOR.Parsing.Parser (2);
      begin
         Large_Bytes (201 .. 203) := [16#59#, 16#10#, 16#00#];
         Flyology_CBOR.Parsing.Initialize (Large, Parser_Profile, Diagnostic);
         Flyology_CBOR.Parsing.Drain (Large, Large_Bytes, True, Events, Result);
         Check
           (Result.Stop = Flyology_CBOR.Parsing.Output_Full
            and then Result.Produced = 2
            and then Result.Consumed = 3
            and then Flyology_CBOR.Parsing.State (Large) = Flyology_CBOR.Parsing.Active
            and then Flyology_CBOR.Parsing.Test_Support.Inspections (Large) = 3,
            "large valid byte payload is not scanned speculatively");
         Flyology_CBOR.Parsing.Abort_Document (Large);
      end;

      declare
         Hostile_Length : Byte_Array (501 .. 1_533) := [others => 0];
         Hostile        : Flyology_CBOR.Parsing.Parser (2);
      begin
         Hostile_Length (501 .. 509) :=
           [16#5B#, 16#FF#, 16#FF#, 16#FF#, 16#FF#,
            16#FF#, 16#FF#, 16#FF#, 16#FF#];
         Flyology_CBOR.Parsing.Initialize (Hostile, Parser_Profile, Diagnostic);
         Flyology_CBOR.Parsing.Drain (Hostile, Hostile_Length, True, Events, Result);
         Check
           (Result.Stop = Flyology_CBOR.Parsing.Output_Full
            and then Result.Consumed = 9
            and then Flyology_CBOR.Parsing.State (Hostile)
              = Flyology_CBOR.Parsing.Failure_Pending
            and then Flyology_CBOR.Parsing.Test_Support.Inspections (Hostile) = 9,
            "hostile declared length uses head-bounded work");
      end;

      declare
         Byte_Input : constant Byte_Array (601 .. 608) :=
           [16#5F#, 16#42#, 1, 2, 16#41#, 3, 16#40#, 16#FF#];
         Text_Input : constant Byte_Array (701 .. 708) :=
           [16#7F#, 16#62#, 16#C3#, 16#A9#, 16#61#, 16#78#, 16#60#, 16#FF#];
         Target     : Flyology_CBOR.Parsing.Parser (2);
         Many       : Flyology_CBOR.Parsing.Event_Array (1 .. 20);
      begin
         Flyology_CBOR.Parsing.Initialize (Target, Parser_Profile, Diagnostic);
         Flyology_CBOR.Parsing.Drain (Target, Byte_Input, True, Many, Result);
         Check
           (Result.Stop = Flyology_CBOR.Parsing.Drain_Document_Complete
            and then Flyology_CBOR.Parsing.Test_Support.Inspections (Target)
              = Interfaces.Unsigned_64 (Byte_Input'Length),
            "indefinite byte string inspects each octet once");
         Flyology_CBOR.Parsing.Reset (Target, Parser_Profile, Diagnostic);
         Flyology_CBOR.Parsing.Drain (Target, Text_Input, True, Many, Result);
         Check
           (Result.Stop = Flyology_CBOR.Parsing.Drain_Document_Complete
            and then Flyology_CBOR.Parsing.Test_Support.Inspections (Target)
              = Interfaces.Unsigned_64 (Text_Input'Length),
            "indefinite text string inspects each octet once");
      end;
   end Test_Drain_Pending_Failure;

   procedure Test_Transport_Differential is
      Input : constant Byte_Array (71 .. 101) :=
        [16#9F#,
         16#1B#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#,
         16#3B#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#,
         16#FA#, 16#3F#, 16#80#, 0, 0,
         16#C0#, 16#F6#,
         16#A1#, 16#18#, 16#18#, 16#F5#,
         16#FF#];
      Empty : constant Byte_Array (1 .. 0) := [];
      subtype Tape is Flyology_CBOR.Parsing.Event_Array (201 .. 240);

      procedure Collect_Step
        (Chunk_Size : Natural;
         Events     : out Tape;
         Count      : out Natural;
         Seed       : Positive := 1)
      is
         Parser     : Flyology_CBOR.Parsing.Parser (12);
         Diagnostic : Flyology_CBOR.Errors.Diagnostic;
         Result     : Flyology_CBOR.Parsing.Step_Result;
         Consumed   : Ada.Streams.Stream_Element_Count := 0;
         Window_End : Offset;
         Window_Size : Positive;
         Calls      : Natural := 0;
         Final_Seen : Boolean := False;
         Random_State : Interfaces.Unsigned_32 := Interfaces.Unsigned_32 (Seed);
      begin
         Count := 0;
         Flyology_CBOR.Parsing.Initialize (Parser, Parser_Profile, Diagnostic);
         loop
            Calls := Calls + 1;
            Check (Calls <= 4 * Input'Length + 16, "Step transport work bound");
            if Consumed = Ada.Streams.Stream_Element_Count (Input'Length) then
               Flyology_CBOR.Parsing.Step (Parser, Empty, True, Result);
            else
               if Chunk_Size = 0 then
                  Random_State := Random_State * 1_664_525 + 1_013_904_223;
                  Window_Size :=
                    1 + Natural
                      (Random_State mod Interfaces.Unsigned_32 (Input'Length));
               else
                  Window_Size := Chunk_Size;
               end if;
               Window_End :=
                 (if Final_Seen
                  then Input'Last
                  else Offset'Min
                    (Input'Last,
                     Input'First + Offset (Consumed) + Offset (Window_Size) - 1));
               Final_Seen := Final_Seen or else Window_End = Input'Last;
               Flyology_CBOR.Parsing.Step
                 (Parser,
                  Input (Input'First + Offset (Consumed) .. Window_End),
                  Window_End = Input'Last,
                  Result);
            end if;
            Consumed := Consumed + Result.Consumed;
            case Result.Outcome is
               when Flyology_CBOR.Parsing.Event_Ready =>
                  Count := Count + 1;
                  Events (Events'First + Offset (Count) - 1) := Result.Item;
               when Flyology_CBOR.Parsing.Need_Input =>
                  null;
               when Flyology_CBOR.Parsing.Document_Complete =>
                  exit;
               when others =>
                  Check (False, "Step transport unexpected outcome");
            end case;
         end loop;
         Check
           (Consumed = Ada.Streams.Stream_Element_Count (Input'Length),
            "Step transport consumes corpus");
      end Collect_Step;

      procedure Collect_Drain
        (Chunk_Size : Natural;
         Capacity   : Positive;
         Events     : out Tape;
         Count      : out Natural;
         Seed       : Positive := 1)
      is
         Parser       : Flyology_CBOR.Parsing.Parser (12);
         Diagnostic   : Flyology_CBOR.Errors.Diagnostic;
         Result       : Flyology_CBOR.Parsing.Drain_Result;
         Consumed     : Ada.Streams.Stream_Element_Count := 0;
         Window_End   : Offset;
         Window_Size  : Positive;
         Calls        : Natural := 0;
         Final_Seen   : Boolean := False;
         Random_State : Interfaces.Unsigned_32 := Interfaces.Unsigned_32 (Seed);
         Batch        : Flyology_CBOR.Parsing.Event_Array (501 .. 508);
      begin
         Count := 0;
         Flyology_CBOR.Parsing.Initialize (Parser, Parser_Profile, Diagnostic);
         loop
            Calls := Calls + 1;
            Check (Calls <= 4 * Input'Length + 16, "Drain transport work bound");
            if Consumed = Ada.Streams.Stream_Element_Count (Input'Length) then
               Flyology_CBOR.Parsing.Drain
                 (Parser, Empty, True, Batch (501 .. 500 + Offset (Capacity)), Result);
            else
               if Chunk_Size = 0 then
                  Random_State := Random_State * 1_664_525 + 1_013_904_223;
                  Window_Size :=
                    1 + Natural
                      (Random_State mod Interfaces.Unsigned_32 (Input'Length));
               else
                  Window_Size := Chunk_Size;
               end if;
               Window_End :=
                 (if Final_Seen
                  then Input'Last
                  else Offset'Min
                    (Input'Last,
                     Input'First + Offset (Consumed) + Offset (Window_Size) - 1));
               Final_Seen := Final_Seen or else Window_End = Input'Last;
               Flyology_CBOR.Parsing.Drain
                 (Parser,
                  Input (Input'First + Offset (Consumed) .. Window_End),
                  Window_End = Input'Last,
                  Batch (501 .. 500 + Offset (Capacity)),
                  Result);
            end if;
            Consumed := Consumed + Result.Consumed;
            for Index in 0 .. Result.Produced - 1 loop
               Count := Count + 1;
               Events (Events'First + Offset (Count) - 1) := Batch (501 + Offset (Index));
            end loop;
            case Result.Stop is
               when Flyology_CBOR.Parsing.Output_Full
                  | Flyology_CBOR.Parsing.Drain_Need_Input =>
                  null;
               when Flyology_CBOR.Parsing.Drain_Document_Complete =>
                  exit;
               when others =>
                  Check (False, "Drain transport unexpected stop");
            end case;
         end loop;
         Check
           (Consumed = Ada.Streams.Stream_Element_Count (Input'Length),
            "Drain transport consumes corpus");
      end Collect_Drain;

      procedure Compare
        (Expected       : Tape;
         Expected_Count : Natural;
         Actual         : Tape;
         Actual_Count   : Natural;
         Context        : String)
      is
      begin
         Check (Actual_Count = Expected_Count, Context & " event count");
         for Index in 0 .. Expected_Count - 1 loop
            declare
               Left  : constant Flyology_CBOR.Parsing.Event :=
                 Expected (Expected'First + Offset (Index));
               Right : constant Flyology_CBOR.Parsing.Event :=
                 Actual (Actual'First + Offset (Index));
            begin
               Check
                 (Flyology_CBOR.Parsing.Kind (Left) = Flyology_CBOR.Parsing.Kind (Right),
                  Context & " event kind");
               Check
                 (Flyology_CBOR.Parsing.Source (Left) = Flyology_CBOR.Parsing.Source (Right),
                  Context & " event source");
               case Flyology_CBOR.Parsing.Kind (Left) is
                  when Flyology_CBOR.Parsing.Unsigned_Value
                     | Flyology_CBOR.Parsing.Negative_Integer_Value =>
                     Check
                       (Flyology_CBOR.Values.Kind
                          (Flyology_CBOR.Parsing.Integer_Data (Left))
                          = Flyology_CBOR.Values.Kind
                            (Flyology_CBOR.Parsing.Integer_Data (Right))
                        and then Flyology_CBOR.Values.Integer_Argument
                          (Flyology_CBOR.Parsing.Integer_Data (Left))
                          = Flyology_CBOR.Values.Integer_Argument
                            (Flyology_CBOR.Parsing.Integer_Data (Right)),
                        Context & " integer payload");
                  when Flyology_CBOR.Parsing.Byte_String_Begin
                     | Flyology_CBOR.Parsing.Byte_String_Chunk_Begin
                     | Flyology_CBOR.Parsing.Text_String_Begin
                     | Flyology_CBOR.Parsing.Text_String_Chunk_Begin
                     | Flyology_CBOR.Parsing.Array_Begin
                     | Flyology_CBOR.Parsing.Map_Begin =>
                     Check
                       (Flyology_CBOR.Values.Kind
                          (Flyology_CBOR.Parsing.Declared_Length (Left))
                          = Flyology_CBOR.Values.Kind
                            (Flyology_CBOR.Parsing.Declared_Length (Right)),
                        Context & " declared length kind");
                     if Flyology_CBOR.Values.Kind
                       (Flyology_CBOR.Parsing.Declared_Length (Left))
                       = Flyology_CBOR.Values.Definite_Length
                     then
                        Check
                          (Flyology_CBOR.Values.Length
                             (Flyology_CBOR.Parsing.Declared_Length (Left))
                             = Flyology_CBOR.Values.Length
                               (Flyology_CBOR.Parsing.Declared_Length (Right)),
                           Context & " declared length payload");
                     end if;
                  when Flyology_CBOR.Parsing.Tag_Begin =>
                     Check
                       (Flyology_CBOR.Parsing.Tag_Data (Left)
                          = Flyology_CBOR.Parsing.Tag_Data (Right),
                        Context & " tag payload");
                  when Flyology_CBOR.Parsing.Simple_Value =>
                     Check
                       (Flyology_CBOR.Parsing.Simple_Data (Left)
                          = Flyology_CBOR.Parsing.Simple_Data (Right),
                        Context & " simple payload");
                  when Flyology_CBOR.Parsing.Float_Value =>
                     Check
                       (Flyology_CBOR.Values.Width
                          (Flyology_CBOR.Parsing.Float_Data (Left))
                          = Flyology_CBOR.Values.Width
                            (Flyology_CBOR.Parsing.Float_Data (Right))
                        and then Flyology_CBOR.Values.Bits
                          (Flyology_CBOR.Parsing.Float_Data (Left))
                          = Flyology_CBOR.Values.Bits
                            (Flyology_CBOR.Parsing.Float_Data (Right)),
                        Context & " float payload");
                  when Flyology_CBOR.Parsing.Byte_String_Fragment
                     | Flyology_CBOR.Parsing.Text_String_Fragment =>
                     Check
                       (Flyology_CBOR.Parsing.Fragment_Kind (Left)
                          = Flyology_CBOR.Parsing.Fragment_Kind (Right)
                        and then Flyology_CBOR.Parsing.Fragment_Source (Left)
                          = Flyology_CBOR.Parsing.Fragment_Source (Right),
                        Context & " fragment payload");
                  when others =>
                     null;
               end case;
            end;
         end loop;
      end Compare;

      Reference       : Tape;
      Reference_Count : Natural;
      Actual          : Tape;
      Actual_Count    : Natural;
   begin
      Collect_Step (Input'Length, Reference, Reference_Count);
      for Chunk_Size in 1 .. Input'Length loop
         Collect_Step (Chunk_Size, Actual, Actual_Count);
         Compare (Reference, Reference_Count, Actual, Actual_Count, "Step schedule");
         for Capacity in 1 .. 8 loop
            Collect_Drain (Chunk_Size, Capacity, Actual, Actual_Count);
            Compare (Reference, Reference_Count, Actual, Actual_Count, "Drain schedule");
         end loop;
      end loop;
      for Seed in 1 .. 32 loop
         Collect_Step (0, Actual, Actual_Count, Seed);
         Compare
           (Reference, Reference_Count, Actual, Actual_Count, "randomized Step schedule");
         for Capacity in 1 .. 8 loop
            Collect_Drain (0, Capacity, Actual, Actual_Count, Seed);
            Compare
              (Reference, Reference_Count, Actual, Actual_Count, "randomized Drain schedule");
         end loop;
      end loop;

      declare
         Parser     : Flyology_CBOR.Parsing.Parser (1);
         Diagnostic : Flyology_CBOR.Errors.Diagnostic;
         Result     : Flyology_CBOR.Parsing.Step_Result;
         Two_Roots  : constant Byte_Array (301 .. 302) := [1, 2];
      begin
         Flyology_CBOR.Parsing.Initialize (Parser, Parser_Profile, Diagnostic);
         Flyology_CBOR.Parsing.Step (Parser, Empty, False, Result);
         Flyology_CBOR.Parsing.Step (Parser, Two_Roots, True, Result);
         Check
           (Result.Outcome = Flyology_CBOR.Parsing.Event_Ready
            and then Result.Consumed = 1,
            "Step stops at admitted event");
         Flyology_CBOR.Parsing.Step (Parser, Two_Roots (302 .. 302), True, Result);
         Check
           (Result.Outcome = Flyology_CBOR.Parsing.Event_Ready
            and then Result.Consumed = 0
            and then Flyology_CBOR.Parsing.Kind (Result.Item)
              = Flyology_CBOR.Parsing.Document_End,
            "suffix remains unconsumed across document end");
         Flyology_CBOR.Parsing.Step (Parser, Two_Roots (302 .. 302), True, Result);
         Check
           (Result.Outcome = Flyology_CBOR.Parsing.Step_Failed
            and then Result.Consumed = 1
            and then Result.Diagnostic.Code = Flyology_CBOR.Errors.Trailing_Input,
            "unconsumed suffix is resubmitted exactly");

         Flyology_CBOR.Parsing.Reset (Parser, Parser_Profile, Diagnostic);
         Flyology_CBOR.Parsing.Step (Parser, Empty, False, Result);
         Flyology_CBOR.Parsing.Step (Parser, Two_Roots (301 .. 301), True, Result);
         Flyology_CBOR.Parsing.Step (Parser, Empty, False, Result);
         Check
           (Result.Outcome = Flyology_CBOR.Parsing.Call_Rejected
            and then Result.Consumed = 0
            and then Result.Diagnostic.Code = Flyology_CBOR.Errors.Final_Input_Retracted,
            "final input cannot be retracted");
      end;
   end Test_Transport_Differential;

   procedure Test_Fragment_Transport is
      Input : constant Byte_Array (301 .. 320) :=
        [16#82#,
         16#5F#, 16#43#, 1, 2, 3, 16#42#, 4, 5, 16#FF#,
         16#7F#, 16#62#, 16#C3#, 16#A9#,
         16#64#, 16#F0#, 16#9F#, 16#92#, 16#A9#, 16#FF#];
      Empty : constant Byte_Array (1 .. 0) := [];
      Expected_Structure : constant Event_Kind_Array :=
        [Flyology_CBOR.Parsing.Document_Begin,
         Flyology_CBOR.Parsing.Array_Begin,
         Flyology_CBOR.Parsing.Byte_String_Begin,
         Flyology_CBOR.Parsing.Byte_String_Chunk_Begin,
         Flyology_CBOR.Parsing.Byte_String_Chunk_End,
         Flyology_CBOR.Parsing.Byte_String_Chunk_Begin,
         Flyology_CBOR.Parsing.Byte_String_Chunk_End,
         Flyology_CBOR.Parsing.Byte_String_End,
         Flyology_CBOR.Parsing.Text_String_Begin,
         Flyology_CBOR.Parsing.Text_String_Chunk_Begin,
         Flyology_CBOR.Parsing.Text_String_Chunk_End,
         Flyology_CBOR.Parsing.Text_String_Chunk_Begin,
         Flyology_CBOR.Parsing.Text_String_Chunk_End,
         Flyology_CBOR.Parsing.Text_String_End,
         Flyology_CBOR.Parsing.Array_End,
         Flyology_CBOR.Parsing.Document_End];

      procedure Run
        (Use_Drain : Boolean;
         Chunk_Size : Natural;
         Capacity   : Positive;
         Seed       : Positive)
      is
         Parser       : Flyology_CBOR.Parsing.Parser (4);
         Diagnostic   : Flyology_CBOR.Errors.Diagnostic;
         Step_Result  : Flyology_CBOR.Parsing.Step_Result;
         Drain_Result : Flyology_CBOR.Parsing.Drain_Result;
         Batch        : Flyology_CBOR.Parsing.Event_Array (1 .. 8);
         Structure    : Event_Kind_Array (1 .. Expected_Structure'Length);
         Structure_Count : Natural := 0;
         Bytes        : Byte_Array (1 .. 5) := [others => 0];
         Text_Bytes   : Byte_Array (1 .. 6) := [others => 0];
         Byte_Count   : Natural := 0;
         Text_Count   : Natural := 0;
         Inline_Count : Natural := 0;
         Consumed     : Ada.Streams.Stream_Element_Count := 0;
         Calls        : Natural := 0;
         Window_End   : Offset;
         Window_Size  : Positive;
         Final_Seen   : Boolean := False;
         Random_State : Interfaces.Unsigned_32 := Interfaces.Unsigned_32 (Seed);
         Complete     : Boolean := False;

         procedure Observe
           (Item          : Flyology_CBOR.Parsing.Event;
            Window        : Byte_Array;
            Window_Origin : Flyology_CBOR.Parsing.Byte_Offset)
         is
            Kind   : constant Flyology_CBOR.Parsing.Event_Kind :=
              Flyology_CBOR.Parsing.Kind (Item);
            Slice  : Flyology_CBOR.Parsing.Chunk_Range;
            Status : Flyology_CBOR.Parsing.Slice_Status;

            procedure Append (Octet : Ada.Streams.Stream_Element) is
            begin
               if Kind = Flyology_CBOR.Parsing.Byte_String_Fragment then
                  Byte_Count := Byte_Count + 1;
                  Bytes (Offset (Byte_Count)) := Octet;
               else
                  Text_Count := Text_Count + 1;
                  Text_Bytes (Offset (Text_Count)) := Octet;
               end if;
            end Append;
         begin
            if Kind in Flyology_CBOR.Parsing.Byte_String_Fragment
              | Flyology_CBOR.Parsing.Text_String_Fragment
            then
               if Flyology_CBOR.Parsing.Fragment_Kind (Item)
                 = Flyology_CBOR.Parsing.Inline_Text_Scalar
               then
                  declare
                     Scalar : constant Flyology_CBOR.Parsing.Inline_Scalar :=
                       Flyology_CBOR.Parsing.Inline_Text (Item);
                  begin
                     Inline_Count := Inline_Count + 1;
                     for Index in 1 .. Scalar.Length loop
                        Append (Scalar.Octets (Offset (Index)));
                     end loop;
                  end;
               else
                  Flyology_CBOR.Parsing.Resolve_Raw_Range
                    (Item,
                     Window_Origin,
                     Ada.Streams.Stream_Element_Count (Window'Length),
                     Slice,
                     Status);
                  Check (Status = Flyology_CBOR.Parsing.Slice_Resolved, "fragment range resolves");
                  for Index in 0 .. Slice.Octet_Length - 1 loop
                     Append (Window (Window'First + Offset (Slice.First_Count + Index)));
                  end loop;
               end if;
            else
               Structure_Count := Structure_Count + 1;
               Structure (Structure_Count) := Kind;
            end if;
         end Observe;
      begin
         Flyology_CBOR.Parsing.Initialize (Parser, Parser_Profile, Diagnostic);
         while not Complete loop
            Calls := Calls + 1;
            Check (Calls <= 8 * Input'Length + 32, "fragment transport work bound");
            if Consumed = Ada.Streams.Stream_Element_Count (Input'Length) then
               if Use_Drain then
                  Flyology_CBOR.Parsing.Drain
                    (Parser, Empty, True, Batch (1 .. Offset (Capacity)), Drain_Result);
               else
                  Flyology_CBOR.Parsing.Step (Parser, Empty, True, Step_Result);
               end if;
            else
               if Chunk_Size = 0 then
                  Random_State := Random_State * 1_664_525 + 1_013_904_223;
                  Window_Size :=
                    1 + Natural
                      (Random_State mod Interfaces.Unsigned_32 (Input'Length));
               else
                  Window_Size := Chunk_Size;
               end if;
               Window_End :=
                 (if Final_Seen
                  then Input'Last
                  else Offset'Min
                    (Input'Last,
                     Input'First + Offset (Consumed) + Offset (Window_Size) - 1));
               Final_Seen := Final_Seen or else Window_End = Input'Last;
               if Use_Drain then
                  Flyology_CBOR.Parsing.Drain
                    (Parser,
                     Input (Input'First + Offset (Consumed) .. Window_End),
                     Final_Seen,
                     Batch (1 .. Offset (Capacity)),
                     Drain_Result);
               else
                  Flyology_CBOR.Parsing.Step
                    (Parser,
                     Input (Input'First + Offset (Consumed) .. Window_End),
                     Final_Seen,
                     Step_Result);
               end if;
            end if;

            if Use_Drain then
               declare
                  Origin : constant Flyology_CBOR.Parsing.Byte_Offset :=
                    Drain_Result.Input_Origin;
                  Window : constant Byte_Array :=
                    (if Consumed = Ada.Streams.Stream_Element_Count (Input'Length)
                     then Empty
                     else Input (Input'First + Offset (Consumed) .. Window_End));
               begin
                  for Index in 0 .. Drain_Result.Produced - 1 loop
                     Observe (Batch (1 + Offset (Index)), Window, Origin);
                  end loop;
               end;
               Consumed := Consumed + Drain_Result.Consumed;
               Complete :=
                 Drain_Result.Stop = Flyology_CBOR.Parsing.Drain_Document_Complete;
               Check
                 (Complete
                  or else Drain_Result.Stop in Flyology_CBOR.Parsing.Output_Full
                    | Flyology_CBOR.Parsing.Drain_Need_Input,
                  "fragment Drain outcome");
            else
               if Step_Result.Outcome = Flyology_CBOR.Parsing.Event_Ready then
                  declare
                     Window : constant Byte_Array :=
                       (if Consumed = Ada.Streams.Stream_Element_Count (Input'Length)
                        then Empty
                        else Input (Input'First + Offset (Consumed) .. Window_End));
                  begin
                     Observe (Step_Result.Item, Window, Step_Result.Input_Origin);
                  end;
               end if;
               Consumed := Consumed + Step_Result.Consumed;
               Complete :=
                 Step_Result.Outcome = Flyology_CBOR.Parsing.Document_Complete;
               Check
                 (Complete
                  or else Step_Result.Outcome in Flyology_CBOR.Parsing.Event_Ready
                    | Flyology_CBOR.Parsing.Need_Input,
                  "fragment Step outcome");
            end if;
         end loop;

         Check (Structure_Count = Expected_Structure'Length, "fragment structural length");
         for Index in Expected_Structure'Range loop
            Check (Structure (Index) = Expected_Structure (Index), "fragment structural event");
         end loop;
         Check (Byte_Count = 5 and then Text_Count = 6, "fragment payload lengths");
         for Index in Bytes'Range loop
            Check (Bytes (Index) = Ada.Streams.Stream_Element (Index), "byte fragment content");
         end loop;
         Check
           (Text_Bytes = [16#C3#, 16#A9#, 16#F0#, 16#9F#, 16#92#, 16#A9#],
            "text fragment content");
         if not Use_Drain and then Chunk_Size = 1 then
            Check (Inline_Count = 2, "one-byte schedule owns both split text scalars");
         end if;
      end Run;
   begin
      for Chunk_Size in 1 .. Input'Length loop
         Run (False, Chunk_Size, 1, 1);
         for Capacity in 1 .. 8 loop
            Run (True, Chunk_Size, Capacity, 1);
         end loop;
      end loop;
      for Seed in 1 .. 32 loop
         Run (False, 0, 1, Seed);
         for Capacity in 1 .. 8 loop
            Run (True, 0, Capacity, Seed);
         end loop;
      end loop;
   end Test_Fragment_Transport;

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

   procedure Test_Writer_Oracle_Bytes is
      Writer     : Flyology_CBOR.Bounded_Writing.Writer (32, 4);
      Diagnostic : Flyology_CBOR.Errors.Diagnostic;
      Float_Item : Flyology_CBOR.Values.Float_Value;
      Status     : Flyology_CBOR.Values.Float_Construction_Status;
      Fragment   : constant Byte_Array (41 .. 42) := [0, 1];
      Output     : Byte_Array (61 .. 92) := [others => 16#AA#];
      Produced   : Ada.Streams.Stream_Element_Count;
      Expected   : constant Byte_Array :=
        [16#9F#,
         16#3B#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#, 16#FF#,
         16#F9#, 16#80#, 0,
         16#5F#, 16#42#, 0, 1, 16#FF#,
         16#F8#, 16#20#,
         16#F4#, 16#F5#, 16#F6#, 16#F7#,
         16#FF#];
   begin
      Flyology_CBOR.Values.Make_Float
        (Flyology_CBOR.Values.Binary16, 16#8000#, Float_Item, Status);
      Check (Status = Flyology_CBOR.Values.Float_Constructed, "writer float construction");
      Flyology_CBOR.Bounded_Writing.Initialize (Writer, Writer_Profile, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Begin_Document (Writer, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Begin_Indefinite_Array (Writer, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Put_Negative_Argument
        (Writer, Interfaces.Unsigned_64'Last, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Put_Float (Writer, Float_Item, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Begin_Indefinite_Byte_String (Writer, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Begin_Byte_String_Chunk (Writer, 2, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Put_Byte_String_Fragment (Writer, Fragment, Diagnostic);
      Flyology_CBOR.Bounded_Writing.End_Byte_String_Chunk (Writer, Diagnostic);
      Flyology_CBOR.Bounded_Writing.End_Byte_String (Writer, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Put_Simple (Writer, 32, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Put_False (Writer, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Put_True (Writer, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Put_Null (Writer, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Put_Undefined (Writer, Diagnostic);
      Flyology_CBOR.Bounded_Writing.End_Array (Writer, Diagnostic);
      Flyology_CBOR.Bounded_Writing.Finish_Document (Writer, Diagnostic);
      Check_Clear (Diagnostic, "writer oracle finish");
      Flyology_CBOR.Bounded_Writing.Copy_Output
        (Writer, Output, Produced, Diagnostic);
      Check
        (Produced = Expected'Length,
         "writer oracle output length");
      for Index in 0 .. Produced - 1 loop
         Check
           (Output (Output'First + Offset (Index)) = Expected (Expected'First + Offset (Index)),
            "writer oracle byte" & Ada.Streams.Stream_Element_Count'Image (Index));
      end loop;
      Check
        (Output (Output'First + Offset (Produced)) = 16#AA#,
         "writer oracle preserves copy suffix");
   end Test_Writer_Oracle_Bytes;

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
         Retry    : Byte_Array (11 .. 18) := [others => 16#AA#];
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
         Flyology_CBOR.Bounded_Writing.Copy_Output
           (Complete, Retry, Produced, Diagnostic);
         Check
            (Diagnostic.Code = Flyology_CBOR.Errors.No_Error
             and then Produced = 3
            and then Retry (11) = 16#19#
            and then Retry (12) = 16#03#
            and then Retry (13) = 16#E8#
             and then Retry (14) = 16#AA#,
            "completed copy remains retryable after capacity denial");
      end;

      for Capacity in 0 .. 9 loop
         declare
            Prefix : Flyology_CBOR.Bounded_Writing.Writer (Capacity, 1);
         begin
            Flyology_CBOR.Bounded_Writing.Initialize (Prefix, Writer_Profile, Diagnostic);
            Flyology_CBOR.Bounded_Writing.Begin_Document (Prefix, Diagnostic);
            Flyology_CBOR.Bounded_Writing.Put_Negative_Argument
              (Prefix, Interfaces.Unsigned_64'Last, Diagnostic);
            if Capacity < 9 then
               Check
                 (Diagnostic.Code = Flyology_CBOR.Errors.Destination_Exhausted
                  and then Flyology_CBOR.Bounded_Writing.Staged_Length (Prefix)
                    = Ada.Streams.Stream_Element_Count (Capacity),
                  "every accepted writer prefix is retained exactly");
            else
               Check
                 (Diagnostic.Code = Flyology_CBOR.Errors.No_Error
                  and then Flyology_CBOR.Bounded_Writing.Staged_Length (Prefix) = 9,
                  "complete nine-byte head fits exact capacity");
            end if;
         end;
      end loop;

      declare
         Deep : Flyology_CBOR.Bounded_Writing.Writer (80, 64);
      begin
         Flyology_CBOR.Bounded_Writing.Initialize (Deep, Writer_Profile, Diagnostic);
         Flyology_CBOR.Bounded_Writing.Begin_Document (Deep, Diagnostic);
         for Index in 1 .. 64 loop
            Flyology_CBOR.Bounded_Writing.Begin_Tag (Deep, 0, Diagnostic);
            Check_Clear (Diagnostic, "writer maximum-depth tag chain");
         end loop;
         Flyology_CBOR.Bounded_Writing.Begin_Tag (Deep, 0, Diagnostic);
         Check
           (Diagnostic.Code = Flyology_CBOR.Errors.Depth_Exhausted
            and then Diagnostic.Offset = 64
            and then Flyology_CBOR.Bounded_Writing.Staged_Length (Deep) = 64,
            "writer hostile tag chain exact work/depth denial");
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
      declare
         Retry : constant Byte_Array := Flyology_CBOR.Allocating_Writing.Output (Writer);
      begin
         Check (Retry'Length = 9 and then Retry (1) = 16#3B#, "allocating output copy retry");
      end;

      declare
         Failing : Flyology_CBOR.Allocating_Writing.Writer (1);
         Raised  : Boolean := False;
      begin
         Flyology_CBOR.Allocating_Writing.Initialize (Failing, Writer_Profile, Diagnostic);
         Flyology_CBOR.Allocating_Writing.Begin_Document (Failing, Diagnostic);
         Flyology_CBOR.Allocating_Writing.Test_Support.Fail_Next_Allocation (Failing);
         begin
            Flyology_CBOR.Allocating_Writing.Put_Null (Failing, Diagnostic);
         exception
            when Storage_Error =>
               Raised := True;
         end;
         Check
           (Raised
            and then Flyology_CBOR.Allocating_Writing.State (Failing)
              = Flyology_CBOR.Allocating_Writing.Failed
            and then Flyology_CBOR.Allocating_Writing.Terminal_Diagnostic (Failing).Code
              = Flyology_CBOR.Errors.Destination_Failed,
            "allocating mutation failure poisons before reraising Storage_Error");
         Flyology_CBOR.Allocating_Writing.Reset (Failing, Writer_Profile, Diagnostic);
         Check_Clear (Diagnostic, "allocating writer resets after storage failure");
      end;

      declare
         Abandoned : Flyology_CBOR.Allocating_Writing.Writer (1);
      begin
         Flyology_CBOR.Allocating_Writing.Initialize (Abandoned, Writer_Profile, Diagnostic);
         Flyology_CBOR.Allocating_Writing.Begin_Document (Abandoned, Diagnostic);
         Flyology_CBOR.Allocating_Writing.Put_Unsigned (Abandoned, 1_000, Diagnostic);
         Check_Clear (Diagnostic, "active allocating writer before scope exit");
      end;
      Check (True, "active allocating writer finalizes without publication or exception");
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

      External_Writing.Reset (Writer, Writer_Profile, Diagnostic);
      Target.Fail_Commit := False;
      Target.Fail_Abort := False;
      Target.Fail_Begin := True;
      External_Writing.Begin_Document (Writer, Target, Diagnostic);
      Check
        (Diagnostic.Code = Flyology_CBOR.Errors.Destination_Failed
         and then External_Writing.State (Writer) = External_Writing.Failed,
         "begin failure poisons without publication");

      External_Writing.Reset (Writer, Writer_Profile, Diagnostic);
      Target.Fail_Begin := False;
      Target.Write_Limit := 1;
      External_Writing.Begin_Document (Writer, Target, Diagnostic);
      External_Writing.Put_Unsigned (Writer, Target, 24, Diagnostic);
      Check
        (Diagnostic.Code = Flyology_CBOR.Errors.Destination_Exhausted
         and then Target.Length = 1
         and then not Target.Published,
         "external exhausted prefix remains staged and unpublished");

      External_Writing.Reset (Writer, Writer_Profile, Diagnostic);
      Target.Write_Limit := 32;
      Target.Fail_Write := True;
      External_Writing.Begin_Document (Writer, Target, Diagnostic);
      External_Writing.Put_Null (Writer, Target, Diagnostic);
      Check
        (Diagnostic.Code = Flyology_CBOR.Errors.Destination_Failed
         and then Target.Length = 0,
         "external failed write accepts no prefix");

      External_Writing.Reset (Writer, Writer_Profile, Diagnostic);
      Target.Fail_Write := False;
      Target.Fail_Abort := True;
      External_Writing.Begin_Document (Writer, Target, Diagnostic);
      External_Writing.Put_Unsigned (Writer, Target, 1, Diagnostic);
      External_Writing.Abort_Document (Writer, Target, Diagnostic);
      Check
        (Diagnostic.Code = Flyology_CBOR.Errors.Abort_Failed
         and then External_Writing.State (Writer) = External_Writing.Failed
         and then not Target.Published,
         "explicit abort failure is primary and unpublished");

      declare
         Raising_Writer : External_Writing.Writer (1);
         Raising_Target : External_Destination;
         Raised         : Boolean := False;
      begin
         External_Writing.Initialize (Raising_Writer, Writer_Profile, Diagnostic);
         External_Writing.Begin_Document (Raising_Writer, Raising_Target, Diagnostic);
         Raising_Target.Raise_Write := True;
         begin
            External_Writing.Put_Null (Raising_Writer, Raising_Target, Diagnostic);
         exception
            when Constraint_Error =>
               Raised := True;
         end;
         Check (Raised, "raising destination callback propagates its exception");
      end;

      declare
         First  : External_Writing.Writer (1);
         Second : External_Writing.Writer (1);
         Shared : External_Destination;
      begin
         External_Writing.Initialize (First, Writer_Profile, Diagnostic);
         External_Writing.Initialize (Second, Writer_Profile, Diagnostic);
         External_Writing.Begin_Document (First, Shared, Diagnostic);
         Check_Clear (Diagnostic, "first shared-target transaction");
         External_Writing.Begin_Document (Second, Shared, Diagnostic);
         Check
           (Diagnostic.Code = Flyology_CBOR.Errors.Destination_Failed
            and then External_Writing.State (Second) = External_Writing.Failed
            and then not Shared.Published,
            "destination detects same-target transaction misuse");
         External_Writing.Abort_Document (First, Shared, Diagnostic);
      end;
   end Test_External_Writer_Transactions;

   procedure Test_Reentrant_Destination_Contract is
      type Reentrant_Destination is limited record
         Inside      : Boolean := False;
         Reentered   : Boolean := False;
         Published   : Boolean := False;
      end record;

      procedure Begin_Callback
        (Target : in out Reentrant_Destination;
         Status : out Flyology_CBOR.Destinations.Begin_Status);
      procedure Write_Callback
        (Target  : in out Reentrant_Destination;
         Data    : Byte_Array;
         Written : out Ada.Streams.Stream_Element_Count;
         Status  : out Flyology_CBOR.Destinations.Write_Status);
      procedure Commit_Callback
        (Target : in out Reentrant_Destination;
         Status : out Flyology_CBOR.Destinations.Commit_Status);
      procedure Abort_Callback
        (Target : in out Reentrant_Destination;
         Status : out Flyology_CBOR.Destinations.Abort_Status);

      package Reentrant_Writing is new Flyology_CBOR.Writing
        (Destination_Type   => Reentrant_Destination,
         Destination_Begin  => Begin_Callback,
         Destination_Write  => Write_Callback,
         Destination_Commit => Commit_Callback,
         Destination_Abort  => Abort_Callback);

      type Writer_Access is access all Reentrant_Writing.Writer;
      type Target_Access is access all Reentrant_Destination;
      Current_Writer : Writer_Access := null;
      Current_Target : Target_Access := null;

      procedure Begin_Callback
        (Target : in out Reentrant_Destination;
         Status : out Flyology_CBOR.Destinations.Begin_Status)
      is
      begin
         Target.Published := False;
         Status := Flyology_CBOR.Destinations.Begin_Succeeded;
      end Begin_Callback;

      procedure Write_Callback
        (Target  : in out Reentrant_Destination;
         Data    : Byte_Array;
         Written : out Ada.Streams.Stream_Element_Count;
         Status  : out Flyology_CBOR.Destinations.Write_Status)
      is
         Nested : Flyology_CBOR.Errors.Diagnostic;
      begin
         if not Target.Inside then
            Target.Inside := True;
            Target.Reentered := True;
            Reentrant_Writing.Put_Null (Current_Writer.all, Current_Target.all, Nested);
            Target.Inside := False;
         end if;
         Written := Ada.Streams.Stream_Element_Count (Data'Length);
         Status := Flyology_CBOR.Destinations.Write_Succeeded;
      end Write_Callback;

      procedure Commit_Callback
        (Target : in out Reentrant_Destination;
         Status : out Flyology_CBOR.Destinations.Commit_Status)
      is
      begin
         Target.Published := True;
         Status := Flyology_CBOR.Destinations.Commit_Succeeded;
      end Commit_Callback;

      procedure Abort_Callback
        (Target : in out Reentrant_Destination;
         Status : out Flyology_CBOR.Destinations.Abort_Status)
      is
         pragma Unreferenced (Target);
      begin
         Status := Flyology_CBOR.Destinations.Abort_Succeeded;
      end Abort_Callback;

      Writer     : aliased Reentrant_Writing.Writer (1);
      Target     : aliased Reentrant_Destination;
      Diagnostic : Flyology_CBOR.Errors.Diagnostic;
      Raised     : Boolean := False;
   begin
      Current_Writer := Writer'Unchecked_Access;
      Current_Target := Target'Unchecked_Access;
      Reentrant_Writing.Initialize (Writer, Writer_Profile, Diagnostic);
      Reentrant_Writing.Begin_Document (Writer, Target, Diagnostic);
      begin
         Reentrant_Writing.Put_Null (Writer, Target, Diagnostic);
      exception
         when others =>
            Raised := True;
      end;
      Check
        (Target.Reentered and then Raised and then not Target.Published,
         "callback reentry is detected or propagated without implicit publication");
   end Test_Reentrant_Destination_Contract;

begin
   Test_Values_And_Numbers;
   Test_Oracle_Scalars;
   Test_Oracle_Structures_And_Strings;
   Test_Parser_Transcript;
   Test_Split_Head_Provenance;
   Test_Parser_Failures_And_Drain;
   Test_Drain_Pending_Failure;
   Test_Transport_Differential;
   Test_Fragment_Transport;
   Test_All_Initial_Octets;
   Test_Bounded_Writer;
   Test_Writer_Oracle_Bytes;
   Test_Writer_Lifecycle;
   Test_Writer_Failures;
   Test_Allocating_Writer;
   Test_External_Writer_Transactions;
   Test_Reentrant_Destination_Contract;
   Ada.Text_IO.Put_Line ("flyology_cbor tests: PASS");
end Flyology_CBOR_Tests;
