with Interfaces;

package body Flyology_CBOR.Parsing is

   use type Ada.Streams.Stream_Element_Count;
   use type Interfaces.Unsigned_64;
   use type Profiles.Profile_Status;

   procedure Clear_Event (Item : out Event) is
      Float_Item   : Values.Float_Value;
      Float_Status : Values.Float_Construction_Status;
   begin
      Values.Make_Float (Values.Binary16, 0, Float_Item, Float_Status);
      Item :=
        (Event_Kind_Value => Document_Begin,
         Source_Value     => (First => 0, Octet_Length => 0),
         Raw_Slice_Value  => False,
         Length_Value     => Values.Indefinite,
         Integer_Value    => Values.Unsigned (0),
         Tag_Value        => 0,
         Simple_Value     => 0,
         Float_Value_Data => Float_Item,
         Fragment_Value   => Borrowed_Input,
         Fragment_Range   => (First => 0, Octet_Length => 0),
         Inline_Value     => (Length => 1, Octets => [others => 0]));
   end Clear_Event;

   procedure Clear_Parser (Self : in out Parser) is
   begin
      Self.Current_Offset := 0;
      Self.Final_Latched := False;
      Self.Document_Started := False;
      Self.Root_Complete := False;
      Self.Document_End_Sent := False;
      Self.Depth := 0;
      Self.Active_String := No_String;
      Self.String_Remaining := 0;
      Self.String_Payload_First := 0;
      Self.Header := [others => 0];
      Self.Header_Have := 0;
      Self.Header_Need := 0;
      Self.Header_Start := 0;
      Self.Header_Was_Split := False;
      Self.Text_Carry := [others => 0];
      Self.Text_Carry_Length := 0;
      Self.Text_Carry_Need := 0;
      Self.Text_Carry_Start := 0;
      Errors.Clear (Self.Last_Diagnostic);
   end Clear_Parser;

   procedure Set_Diagnostic
     (Item             : out Errors.Diagnostic;
      Code             : Errors.Error_Code;
      Offset           : Byte_Offset;
      Has_Construct    : Boolean := False;
      Construct_Offset : Byte_Offset := 0)
   is
   begin
      Errors.Clear (Item);
      Item.Code := Code;
      Item.Coordinate := Errors.Source_Byte;
      Item.Offset := Offset;
      Item.Has_Construct_Offset := Has_Construct;
      Item.Construct_Offset := Construct_Offset;
   end Set_Diagnostic;

   function Kind (Item : Event) return Event_Kind is
     (Item.Event_Kind_Value);

   function Source (Item : Event) return Source_Range is
     (Item.Source_Value);

   function Has_Raw_Slice (Item : Event) return Boolean is
     (Item.Raw_Slice_Value);

   procedure Resolve_Raw_Range
     (Item          : Event;
      Window_Origin : Byte_Offset;
      Window_Length : Ada.Streams.Stream_Element_Count;
      Slice         : out Chunk_Range;
      Status        : out Slice_Status)
   is
      Difference : Byte_Offset;
      Available : Byte_Offset;
   begin
      Slice := (First_Count => 0, Octet_Length => 0);
      if not Item.Raw_Slice_Value then
         Status := No_Raw_Slice;
         return;
      elsif Item.Source_Value.First < Window_Origin then
         Status := Range_Outside_Window;
         return;
      end if;

      Difference := Item.Source_Value.First - Window_Origin;
      if Difference > Byte_Offset (Window_Length) then
         Status := Range_Outside_Window;
         return;
      end if;

      Available := Byte_Offset (Window_Length) - Difference;
      if Item.Source_Value.Octet_Length > Available then
         Status := Range_Outside_Window;
         return;
      end if;

      Slice :=
        (First_Count  => Ada.Streams.Stream_Element_Count (Difference),
         Octet_Length => Ada.Streams.Stream_Element_Count (Item.Source_Value.Octet_Length));
      Status := Slice_Resolved;
   end Resolve_Raw_Range;

   function Declared_Length (Item : Event) return Values.Item_Length is
     (Item.Length_Value);

   function Integer_Data (Item : Event) return Values.Integer_Value is
     (Item.Integer_Value);

   function Tag_Data (Item : Event) return Values.Tag_Number is
     (Item.Tag_Value);

   function Simple_Data (Item : Event) return Values.Simple_Code is
     (Item.Simple_Value);

   function Float_Data (Item : Event) return Values.Float_Value is
     (Item.Float_Value_Data);

   function Fragment_Kind (Item : Event) return Fragment_Representation is
     (Item.Fragment_Value);

   function Fragment_Source (Item : Event) return Source_Range is
     (Item.Fragment_Range);

   function Inline_Text (Item : Event) return Inline_Scalar is
     (Item.Inline_Value);

   procedure Apply_Profile
     (Self       : in out Parser;
      Profile    : Profiles.Parser_Profile;
      Diagnostic : out Errors.Diagnostic)
   is
      Status : constant Profiles.Profile_Status := Profiles.Validate (Profile);
   begin
      Clear_Parser (Self);
      Self.Profile_Applied := Status = Profiles.Profile_Supported;
      Self.Profile_Value := Profile;

      case Status is
         when Profiles.Profile_Supported =>
            Self.Current_State := Ready;
            Errors.Clear (Diagnostic);
         when Profiles.Profile_Unsupported =>
            Self.Current_State := Failed;
            Set_Diagnostic (Diagnostic, Errors.Unsupported_Profile, 0);
            Self.Last_Diagnostic := Diagnostic;
         when Profiles.Profile_Incompatible =>
            Self.Current_State := Failed;
            Set_Diagnostic (Diagnostic, Errors.Incompatible_Profile, 0);
            Self.Last_Diagnostic := Diagnostic;
      end case;
   end Apply_Profile;

   procedure Initialize
     (Self       : in out Parser;
      Profile    : Profiles.Parser_Profile;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      if Self.Current_State /= Uninitialized then
         Set_Diagnostic (Diagnostic, Errors.Invalid_State, Self.Current_Offset);
         return;
      end if;

      Apply_Profile (Self, Profile, Diagnostic);
   end Initialize;

   procedure Step
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Result       : out Step_Result)
   is
      type Head_Outcome is (Head_Ready, Head_Need_Input, Head_Error);

      Origin   : constant Byte_Offset := Self.Current_Offset;
      Consumed : Ada.Streams.Stream_Element_Count := 0;

      function Input_Available return Boolean is
        (Consumed < Ada.Streams.Stream_Element_Count (Input'Length));

      function Current_Byte return Ada.Streams.Stream_Element is
        (Input
           (Input'First
            + Ada.Streams.Stream_Element_Offset (Consumed)));

      procedure Finish_Result
        (Outcome    : Step_Outcome;
         Diagnostic : Errors.Diagnostic)
      is
      begin
         Result.Outcome := Outcome;
         Result.Input_Origin := Origin;
         Result.Consumed := Consumed;
         Result.Diagnostic := Diagnostic;
      end Finish_Result;

      procedure Clear_Result (Outcome : Step_Outcome) is
         Diagnostic : Errors.Diagnostic;
      begin
         Errors.Clear (Diagnostic);
         Finish_Result (Outcome, Diagnostic);
      end Clear_Result;

      procedure Fail
        (Code             : Errors.Error_Code;
         Offset           : Byte_Offset;
         Has_Construct    : Boolean := False;
         Construct_Offset : Byte_Offset := 0)
      is
      begin
         Set_Diagnostic
           (Result.Diagnostic,
            Code,
            Offset,
            Has_Construct,
            Construct_Offset);
         Result.Outcome := Step_Failed;
         Result.Input_Origin := Origin;
         Result.Consumed := Consumed;
         Self.Last_Diagnostic := Result.Diagnostic;
         Self.Current_State := Failed;
      end Fail;

      function Consume_Byte
        (Value : out Ada.Streams.Stream_Element) return Boolean
      is
      begin
         if not Input_Available then
            return False;
         elsif Self.Current_Offset = Byte_Offset'Last then
            Fail (Errors.Offset_Exhausted, Self.Current_Offset);
            return False;
         end if;

         Value := Current_Byte;
         Consumed := Consumed + 1;
         Self.Current_Offset := Self.Current_Offset + 1;
         return True;
      end Consume_Byte;

      procedure Emit
        (Kind_Value : Event_Kind;
         First      : Byte_Offset;
         Length     : Byte_Offset;
         Raw        : Boolean)
      is
      begin
         Clear_Event (Result.Item);
         Result.Item.Event_Kind_Value := Kind_Value;
         Result.Item.Source_Value := (First => First, Octet_Length => Length);
         Result.Item.Raw_Slice_Value := Raw;
         Clear_Result (Event_Ready);
      end Emit;

      procedure Complete_Item is
      begin
         if Self.Depth = 0 then
            Self.Root_Complete := True;
            return;
         end if;

         case Self.Stack (Self.Depth).Kind is
            when Array_Frame =>
               if not Self.Stack (Self.Depth).Indefinite then
                  Self.Stack (Self.Depth).Remaining := Self.Stack (Self.Depth).Remaining - 1;
               end if;
            when Map_Frame =>
               if Self.Stack (Self.Depth).Expecting_Key then
                  Self.Stack (Self.Depth).Expecting_Key := False;
               else
                  Self.Stack (Self.Depth).Expecting_Key := True;
                  if not Self.Stack (Self.Depth).Indefinite then
                     Self.Stack (Self.Depth).Remaining := Self.Stack (Self.Depth).Remaining - 1;
                  end if;
               end if;
            when Tag_Frame =>
               Self.Stack (Self.Depth).Child_Done := True;
            when Indefinite_Byte_String_Frame | Indefinite_Text_String_Frame =>
               null;
         end case;
      end Complete_Item;

      function Push
        (Kind          : Frame_Kind;
         Indefinite    : Boolean := False;
         Remaining     : Values.Argument := 0;
         Expecting_Key : Boolean := True) return Boolean
      is
      begin
         if Self.Depth = Self.Maximum_Syntax_Depth then
            Fail
              (Errors.Depth_Exhausted,
               Self.Header_Start,
               True,
               Self.Header_Start);
            return False;
         end if;

         Self.Depth := Self.Depth + 1;
         Self.Stack (Self.Depth) :=
           (Kind          => Kind,
            Indefinite    => Indefinite,
            Remaining     => Remaining,
            Expecting_Key => Expecting_Key,
            Child_Done    => False);
         return True;
      end Push;

      procedure Read_Head
        (Outcome    : out Head_Outcome;
         Major      : out Natural;
         Argument   : out Interfaces.Unsigned_64;
         Indefinite : out Boolean;
         Raw        : out Boolean)
      is
         Octet : Ada.Streams.Stream_Element;
         AI    : Natural;
      begin
         Major := 0;
         Argument := 0;
         Indefinite := False;
         Raw := False;

         if Self.Header_Have = 0 then
            if not Input_Available then
               if End_Of_Input then
                  Fail
                    (Errors.Truncated_Input,
                     Self.Current_Offset,
                     True,
                     Self.Current_Offset);
                  Outcome := Head_Error;
               else
                  Clear_Result (Need_Input);
                  Outcome := Head_Need_Input;
               end if;
               return;
            end if;

            Self.Header_Start := Self.Current_Offset;
            Self.Header_Was_Split := False;
            if not Consume_Byte (Octet) then
               Outcome := Head_Error;
               return;
            end if;
            Self.Header_Have := 1;
            Self.Header (1) := Octet;
            AI := Natural (Octet) mod 32;
            case AI is
               when 0 .. 23 =>
                  Self.Header_Need := 1;
               when 24 =>
                  Self.Header_Need := 2;
               when 25 =>
                  Self.Header_Need := 3;
               when 26 =>
                  Self.Header_Need := 5;
               when 27 =>
                  Self.Header_Need := 9;
               when 28 .. 30 =>
                  Fail
                    (Errors.Reserved_Additional_Information,
                     Self.Header_Start,
                     True,
                     Self.Header_Start);
                  Self.Header_Have := 0;
                  Self.Header_Need := 0;
                  Outcome := Head_Error;
                  return;
               when 31 =>
                  Self.Header_Need := 1;
               when others =>
                  raise Program_Error;
            end case;
         end if;

         while Self.Header_Have < Self.Header_Need loop
            if not Input_Available then
               Self.Header_Was_Split := True;
               if End_Of_Input then
                  Fail
                    (Errors.Truncated_Input,
                     Self.Current_Offset,
                     True,
                     Self.Header_Start);
                  Outcome := Head_Error;
               else
                  Clear_Result (Need_Input);
                  Outcome := Head_Need_Input;
               end if;
               return;
            end if;

            if not Consume_Byte (Octet) then
               Outcome := Head_Error;
               return;
            end if;
            Self.Header_Have := Self.Header_Have + 1;
            Self.Header (Self.Header_Have) := Octet;
         end loop;

         Major := Natural (Self.Header (1)) / 32;
         AI := Natural (Self.Header (1)) mod 32;
         Indefinite := AI = 31;
         if AI <= 23 then
            Argument := Interfaces.Unsigned_64 (AI);
         elsif AI <= 27 then
            for Index in 2 .. Self.Header_Need loop
               Argument := Interfaces.Shift_Left (Argument, 8);
               Argument := Argument or Interfaces.Unsigned_64 (Self.Header (Index));
            end loop;
         end if;
         Raw := not Self.Header_Was_Split;
         Self.Header_Have := 0;
         Self.Header_Need := 0;
         Self.Header_Was_Split := False;
         Outcome := Head_Ready;
      end Read_Head;

      procedure Emit_String_Fragment is
         Octet         : Ada.Streams.Stream_Element;
         Start         : Byte_Offset;
         Fragment_Size : Interfaces.Unsigned_64 := 0;

         procedure UTF8_Failure
           (Offset           : Byte_Offset;
            Construct_Offset : Byte_Offset)
         is
         begin
            Fail
              (Errors.Invalid_UTF8,
               Offset,
               True,
               Construct_Offset);
         end UTF8_Failure;

         function Valid_Continuation
           (Lead     : Ada.Streams.Stream_Element;
            Position : Positive;
            Value    : Ada.Streams.Stream_Element) return Boolean
         is
            Number : constant Natural := Natural (Value);
         begin
            if Position /= 2 then
               return Number in 16#80# .. 16#BF#;
            end if;

            case Natural (Lead) is
               when 16#E0# =>
                  return Number in 16#A0# .. 16#BF#;
               when 16#ED# =>
                  return Number in 16#80# .. 16#9F#;
               when 16#F0# =>
                  return Number in 16#90# .. 16#BF#;
               when 16#F4# =>
                  return Number in 16#80# .. 16#8F#;
               when others =>
                  return Number in 16#80# .. 16#BF#;
            end case;
         end Valid_Continuation;

         function Needed_Octets
           (Value : Ada.Streams.Stream_Element) return Natural
         is
            Number : constant Natural := Natural (Value);
         begin
            if Number <= 16#7F# then
               return 1;
            elsif Number in 16#C2# .. 16#DF# then
               return 2;
            elsif Number in 16#E0# .. 16#EF# then
               return 3;
            elsif Number in 16#F0# .. 16#F4# then
               return 4;
            else
               return 0;
            end if;
         end Needed_Octets;
      begin
         if End_Of_Input then
            declare
               Available : constant Interfaces.Unsigned_64 :=
                 Interfaces.Unsigned_64
                   (Ada.Streams.Stream_Element_Count (Input'Length) - Consumed);
            begin
               if Available < Self.String_Remaining then
                  if Available > Byte_Offset'Last - Self.Current_Offset then
                     Fail (Errors.Offset_Exhausted, Self.Current_Offset);
                  else
                     Fail
                       (Errors.Truncated_Input,
                        Self.Current_Offset + Available,
                        True,
                        Self.String_Payload_First);
                  end if;
                  return;
               end if;
            end;
         end if;

         if Self.Active_String in Definite_Byte_String | Byte_String_Chunk then
            if not Input_Available then
               if End_Of_Input then
                  Fail
                    (Errors.Truncated_Input,
                     Self.Current_Offset,
                     True,
                     Self.String_Payload_First);
               else
                  Clear_Result (Need_Input);
               end if;
               return;
            end if;

            Start := Self.Current_Offset;
            while Input_Available
              and then Self.String_Remaining > 0
            loop
               if not Consume_Byte (Octet) then
                  return;
               end if;
               Self.String_Remaining := Self.String_Remaining - 1;
               Fragment_Size := Fragment_Size + 1;
            end loop;
            Emit (Byte_String_Fragment, Start, Fragment_Size, True);
            Result.Item.Fragment_Value := Borrowed_Input;
            Result.Item.Fragment_Range :=
              (First => Start, Octet_Length => Fragment_Size);
            return;
         end if;

         if Self.Text_Carry_Length = 0 then
            if not Input_Available then
               if End_Of_Input then
                  Fail
                    (Errors.Truncated_Input,
                     Self.Current_Offset,
                     True,
                     Self.String_Payload_First);
               else
                  Clear_Result (Need_Input);
               end if;
               return;
            end if;

            Start := Self.Current_Offset;
            if not Consume_Byte (Octet) then
               return;
            end if;
            Self.String_Remaining := Self.String_Remaining - 1;
            Self.Text_Carry_Start := Start;
            Self.Text_Carry (1) := Octet;
            Self.Text_Carry_Length := 1;
            Self.Text_Carry_Need := Needed_Octets (Octet);
            if Self.Text_Carry_Need = 0 then
               UTF8_Failure (Start, Start);
               return;
            elsif Self.Text_Carry_Need = 1 then
               Self.Text_Carry_Length := 0;
               Self.Text_Carry_Need := 0;
               Emit (Text_String_Fragment, Start, 1, True);
               Result.Item.Fragment_Value := Borrowed_Input;
               Result.Item.Fragment_Range := (First => Start, Octet_Length => 1);
               return;
            end if;
         end if;

         while Self.Text_Carry_Length < Self.Text_Carry_Need loop
            if Self.String_Remaining = 0 then
               UTF8_Failure (Self.Current_Offset, Self.Text_Carry_Start);
               return;
            elsif not Input_Available then
               if End_Of_Input then
                  UTF8_Failure (Self.Current_Offset, Self.Text_Carry_Start);
               else
                  Clear_Result (Need_Input);
               end if;
               return;
            end if;

            Start := Self.Current_Offset;
            if not Consume_Byte (Octet) then
               return;
            end if;
            Self.String_Remaining := Self.String_Remaining - 1;
            if not Valid_Continuation
              (Self.Text_Carry (1), Self.Text_Carry_Length + 1, Octet)
            then
               UTF8_Failure (Start, Start);
               return;
            end if;
            Self.Text_Carry_Length := Self.Text_Carry_Length + 1;
            Self.Text_Carry
              (Ada.Streams.Stream_Element_Offset (Self.Text_Carry_Length)) := Octet;
         end loop;

         Emit
           (Text_String_Fragment,
            Self.Text_Carry_Start,
            Byte_Offset (Self.Text_Carry_Length),
            False);
         Result.Item.Fragment_Value := Inline_Text_Scalar;
         Result.Item.Fragment_Range :=
           (First        => Self.Text_Carry_Start,
            Octet_Length => Byte_Offset (Self.Text_Carry_Length));
         Result.Item.Inline_Value.Length := Self.Text_Carry_Length;
         Result.Item.Inline_Value.Octets := Self.Text_Carry;
         Self.Text_Carry_Length := 0;
         Self.Text_Carry_Need := 0;
      end Emit_String_Fragment;

      Diagnostic    : Errors.Diagnostic;
      Head_Status   : Head_Outcome;
      Major         : Natural;
      Argument      : Interfaces.Unsigned_64;
      Is_Indefinite : Boolean;
      Raw           : Boolean;
      First         : Byte_Offset;
      Head_Length   : Byte_Offset;
      Octet         : Ada.Streams.Stream_Element;
      Float_Item    : Values.Float_Value;
      Float_Status  : Values.Float_Construction_Status;
   begin
      Clear_Event (Result.Item);
      Errors.Clear (Result.Diagnostic);
      Result :=
        (Outcome      => Call_Rejected,
         Input_Origin => Origin,
         Consumed     => 0,
         Item         => Result.Item,
         Diagnostic   => Result.Diagnostic);

      if Self.Current_State = Failure_Pending then
         Result.Outcome := Step_Failed;
         Result.Diagnostic := Self.Last_Diagnostic;
         Self.Current_State := Failed;
         return;
      elsif Self.Current_State not in Ready | Active then
         Set_Diagnostic (Diagnostic, Errors.Invalid_State, Self.Current_Offset);
         Finish_Result (Call_Rejected, Diagnostic);
         return;
      elsif Self.Final_Latched and then not End_Of_Input then
         Set_Diagnostic (Diagnostic, Errors.Final_Input_Retracted, Self.Current_Offset);
         Finish_Result (Call_Rejected, Diagnostic);
         return;
      end if;

      if End_Of_Input then
         Self.Final_Latched := True;
      end if;

      if not Self.Document_Started then
         Self.Document_Started := True;
         Self.Current_State := Active;
         Emit (Document_Begin, Self.Current_Offset, 0, False);
         return;
      end if;

      if Self.Document_End_Sent then
         if Input_Available then
            First := Self.Current_Offset;
            if not Consume_Byte (Octet) then
               return;
            end if;
            Fail (Errors.Trailing_Input, First, True, First);
         elsif Self.Final_Latched then
            Self.Current_State := Completed;
            Clear_Result (Document_Complete);
         else
            Clear_Result (Need_Input);
         end if;
         return;
      elsif Self.Root_Complete then
         Self.Document_End_Sent := True;
         Emit (Document_End, Self.Current_Offset, 0, False);
         return;
      end if;

      if Self.Active_String /= No_String then
         if Self.String_Remaining > 0 then
            Emit_String_Fragment;
            return;
         elsif Self.Text_Carry_Length /= 0 then
            Fail
              (Errors.Invalid_UTF8,
               Self.Current_Offset,
               True,
               Self.Text_Carry_Start);
            return;
         end if;

         First := Self.Current_Offset;
         case Self.Active_String is
            when Definite_Byte_String =>
               Self.Active_String := No_String;
               Emit (Byte_String_End, First, 0, False);
               Complete_Item;
            when Definite_Text_String =>
               Self.Active_String := No_String;
               Emit (Text_String_End, First, 0, False);
               Complete_Item;
            when Byte_String_Chunk =>
               Self.Active_String := No_String;
               Emit (Byte_String_Chunk_End, First, 0, False);
            when Text_String_Chunk =>
               Self.Active_String := No_String;
               Emit (Text_String_Chunk_End, First, 0, False);
            when No_String =>
               null;
         end case;
         return;
      end if;

      if Self.Depth > 0 then
         case Self.Stack (Self.Depth).Kind is
            when Tag_Frame =>
               if Self.Stack (Self.Depth).Child_Done then
                  Self.Depth := Self.Depth - 1;
                  Emit (Tag_End, Self.Current_Offset, 0, False);
                  Complete_Item;
                  return;
               end if;
            when Array_Frame =>
               if not Self.Stack (Self.Depth).Indefinite
                 and then Self.Stack (Self.Depth).Remaining = 0
               then
                  Self.Depth := Self.Depth - 1;
                  Emit (Array_End, Self.Current_Offset, 0, False);
                  Complete_Item;
                  return;
               end if;
            when Map_Frame =>
               if not Self.Stack (Self.Depth).Indefinite
                 and then Self.Stack (Self.Depth).Remaining = 0
                 and then Self.Stack (Self.Depth).Expecting_Key
               then
                  Self.Depth := Self.Depth - 1;
                  Emit (Map_End, Self.Current_Offset, 0, False);
                  Complete_Item;
                  return;
               end if;
            when Indefinite_Byte_String_Frame | Indefinite_Text_String_Frame =>
               null;
         end case;
      end if;

      First := Self.Current_Offset;
      Read_Head (Head_Status, Major, Argument, Is_Indefinite, Raw);
      if Head_Status /= Head_Ready then
         return;
      end if;
      Head_Length := Self.Current_Offset - First;

      if Is_Indefinite then
         if Major = 7 then
            if Self.Depth = 0 then
               Fail (Errors.Unexpected_Break, First, True, First);
               return;
            end if;

            case Self.Stack (Self.Depth).Kind is
               when Array_Frame =>
                  if not Self.Stack (Self.Depth).Indefinite then
                     Fail (Errors.Unexpected_Break, First, True, First);
                     return;
                  end if;
                  Self.Depth := Self.Depth - 1;
                  Emit (Array_End, First, 1, Raw);
                  Complete_Item;
               when Map_Frame =>
                  if not Self.Stack (Self.Depth).Indefinite then
                     Fail (Errors.Unexpected_Break, First, True, First);
                  elsif not Self.Stack (Self.Depth).Expecting_Key then
                     Fail (Errors.Odd_Map, First, True, First);
                  else
                     Self.Depth := Self.Depth - 1;
                     Emit (Map_End, First, 1, Raw);
                     Complete_Item;
                  end if;
               when Indefinite_Byte_String_Frame =>
                  Self.Depth := Self.Depth - 1;
                  Emit (Byte_String_End, First, 1, Raw);
                  Complete_Item;
               when Indefinite_Text_String_Frame =>
                  Self.Depth := Self.Depth - 1;
                  Emit (Text_String_End, First, 1, Raw);
                  Complete_Item;
               when Tag_Frame =>
                  Fail (Errors.Unexpected_Break, First, True, First);
            end case;
            return;
         elsif Major not in 2 .. 5 then
            Fail (Errors.Invalid_Indefinite_Item, First, True, First);
            return;
         end if;
      end if;

      if Self.Depth > 0
        and then Self.Stack (Self.Depth).Kind
          in Indefinite_Byte_String_Frame | Indefinite_Text_String_Frame
      then
         if Is_Indefinite
           or else (Self.Stack (Self.Depth).Kind = Indefinite_Byte_String_Frame and then Major /= 2)
           or else (Self.Stack (Self.Depth).Kind = Indefinite_Text_String_Frame and then Major /= 3)
         then
            Fail (Errors.Invalid_String_Chunk, First, True, First);
            return;
         end if;

         Self.String_Remaining := Argument;
         Self.String_Payload_First := Self.Current_Offset;
         if Major = 2 then
            Self.Active_String := Byte_String_Chunk;
            Emit (Byte_String_Chunk_Begin, First, Head_Length, Raw);
         else
            Self.Active_String := Text_String_Chunk;
            Emit (Text_String_Chunk_Begin, First, Head_Length, Raw);
         end if;
         Result.Item.Length_Value := Values.Definite (Argument);
         return;
      end if;

      case Major is
         when 0 =>
            Emit (Unsigned_Value, First, Head_Length, Raw);
            Result.Item.Integer_Value := Values.Unsigned (Argument);
            Complete_Item;
         when 1 =>
            Emit (Negative_Integer_Value, First, Head_Length, Raw);
            Result.Item.Integer_Value := Values.Negative (Argument);
            Complete_Item;
         when 2 =>
            if Is_Indefinite then
               if not Push (Indefinite_Byte_String_Frame, True) then
                  return;
               end if;
               Emit (Byte_String_Begin, First, Head_Length, Raw);
               Result.Item.Length_Value := Values.Indefinite;
            else
               Self.Active_String := Definite_Byte_String;
               Self.String_Remaining := Argument;
               Self.String_Payload_First := Self.Current_Offset;
               Emit (Byte_String_Begin, First, Head_Length, Raw);
               Result.Item.Length_Value := Values.Definite (Argument);
            end if;
         when 3 =>
            if Is_Indefinite then
               if not Push (Indefinite_Text_String_Frame, True) then
                  return;
               end if;
               Emit (Text_String_Begin, First, Head_Length, Raw);
               Result.Item.Length_Value := Values.Indefinite;
            else
               Self.Active_String := Definite_Text_String;
               Self.String_Remaining := Argument;
               Self.String_Payload_First := Self.Current_Offset;
               Emit (Text_String_Begin, First, Head_Length, Raw);
               Result.Item.Length_Value := Values.Definite (Argument);
            end if;
         when 4 =>
            if not Push (Array_Frame, Is_Indefinite, Argument) then
               return;
            end if;
            Emit (Array_Begin, First, Head_Length, Raw);
            Result.Item.Length_Value :=
              (if Is_Indefinite then Values.Indefinite else Values.Definite (Argument));
         when 5 =>
            if not Push (Map_Frame, Is_Indefinite, Argument, True) then
               return;
            end if;
            Emit (Map_Begin, First, Head_Length, Raw);
            Result.Item.Length_Value :=
              (if Is_Indefinite then Values.Indefinite else Values.Definite (Argument));
         when 6 =>
            if not Push (Tag_Frame) then
               return;
            end if;
            Emit (Tag_Begin, First, Head_Length, Raw);
            Result.Item.Tag_Value := Argument;
         when 7 =>
            declare
               AI : constant Natural := Natural (Self.Header (1)) mod 32;
            begin
               if AI < 20 then
                  Emit (Simple_Value, First, Head_Length, Raw);
                  Result.Item.Simple_Value := Values.Simple_Code (Argument);
                  Complete_Item;
               elsif AI = 20 then
                  Emit (False_Value, First, Head_Length, Raw);
                  Complete_Item;
               elsif AI = 21 then
                  Emit (True_Value, First, Head_Length, Raw);
                  Complete_Item;
               elsif AI = 22 then
                  Emit (Null_Value, First, Head_Length, Raw);
                  Complete_Item;
               elsif AI = 23 then
                  Emit (Undefined_Value, First, Head_Length, Raw);
                  Complete_Item;
               elsif AI = 24 then
                  if Argument < 32 then
                     Fail (Errors.Invalid_Simple_Value, First, True, First);
                  else
                     Emit (Simple_Value, First, Head_Length, Raw);
                     Result.Item.Simple_Value := Values.Simple_Code (Argument);
                     Complete_Item;
                  end if;
               elsif AI in 25 .. 27 then
                  Values.Make_Float
                    ((case AI is
                        when 25 => Values.Binary16,
                        when 26 => Values.Binary32,
                        when others => Values.Binary64),
                     Argument,
                     Float_Item,
                     Float_Status);
                  Emit (Float_Value, First, Head_Length, Raw);
                  Result.Item.Float_Value_Data := Float_Item;
                  Complete_Item;
               else
                  Fail (Errors.Unexpected_Initial_Byte, First, True, First);
               end if;
            end;
         when others =>
            Fail (Errors.Unexpected_Initial_Byte, First, True, First);
      end case;
   end Step;

   procedure Drain
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Events       : in out Event_Array;
      Result       : out Drain_Result)
   is
      Origin   : constant Byte_Offset := Self.Current_Offset;
      Consumed : Ada.Streams.Stream_Element_Count := 0;
      Produced : Ada.Streams.Stream_Element_Count := 0;
      One      : Step_Result;
      Last     : Ada.Streams.Stream_Element_Offset;
      Empty    : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
   begin
      Errors.Clear (Result.Diagnostic);
      Result :=
        (Stop         => Output_Full,
         Input_Origin => Origin,
         Consumed     => 0,
         Produced     => 0,
         Diagnostic   => Result.Diagnostic);

      if Events'Length = 0 then
         return;
      end if;

      loop
         if Consumed = Ada.Streams.Stream_Element_Count (Input'Length) then
            Step (Self, Empty, End_Of_Input, One);
         else
            Last := Input'Last;
            Step
              (Self,
               Input
                 (Input'First + Ada.Streams.Stream_Element_Offset (Consumed) .. Last),
               End_Of_Input,
               One);
         end if;
         Consumed := Consumed + One.Consumed;

         case One.Outcome is
            when Event_Ready =>
               Events
                 (Events'First + Ada.Streams.Stream_Element_Offset (Produced)) := One.Item;
               Produced := Produced + 1;
               if Produced = Ada.Streams.Stream_Element_Count (Events'Length) then
                  Result.Stop := Output_Full;
                  exit;
               end if;
            when Need_Input =>
               Result.Stop := Drain_Need_Input;
               exit;
            when Document_Complete =>
               Result.Stop := Drain_Document_Complete;
               exit;
            when Step_Failed =>
               Result.Stop := Drain_Failed;
               Result.Diagnostic := One.Diagnostic;
               exit;
            when Call_Rejected =>
               Result.Stop := Drain_Rejected;
               Result.Diagnostic := One.Diagnostic;
               exit;
         end case;
      end loop;

      Result.Input_Origin := Origin;
      Result.Consumed := Consumed;
      Result.Produced := Produced;
   end Drain;

   procedure Abort_Document (Self : in out Parser) is
   begin
      case Self.Current_State is
         when Ready | Active =>
            Self.Current_State := Aborted;
            Errors.Clear (Self.Last_Diagnostic);
         when Failure_Pending =>
            Self.Current_State := Failed;
         when Uninitialized | Completed | Failed | Aborted =>
            null;
      end case;
   end Abort_Document;

   procedure Reset
     (Self       : in out Parser;
      Profile    : Profiles.Parser_Profile;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      if Self.Current_State not in Failure_Pending | Completed | Failed | Aborted then
         Set_Diagnostic (Diagnostic, Errors.Invalid_State, Self.Current_Offset);
         return;
      end if;

      Apply_Profile (Self, Profile, Diagnostic);
   end Reset;

   function State (Self : Parser) return Parser_State is
     (Self.Current_State);

   function Has_Applied_Profile (Self : Parser) return Boolean is
     (Self.Profile_Applied);

   function Applied_Profile (Self : Parser) return Profiles.Parser_Profile is
     (Self.Profile_Value);

   function Terminal_Diagnostic (Self : Parser) return Errors.Diagnostic is
     (Self.Last_Diagnostic);

end Flyology_CBOR.Parsing;
