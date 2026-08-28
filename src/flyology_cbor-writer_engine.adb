package body Flyology_CBOR.Writer_Engine is

   use type Destinations.Abort_Status;
   use type Destinations.Begin_Status;
   use type Destinations.Commit_Status;
   use type Destinations.Write_Status;
   use type Errors.Error_Code;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_64;
   use type Profiles.Profile_Status;

   procedure Set_Diagnostic
     (Item       : out Errors.Diagnostic;
      Code       : Errors.Error_Code;
      Coordinate : Errors.Coordinate_Kind;
      Offset     : Interfaces.Unsigned_64)
   is
   begin
      Errors.Clear (Item);
      Item.Code := Code;
      Item.Coordinate := Coordinate;
      Item.Offset := Offset;
   end Set_Diagnostic;

   procedure Clear_Transaction (Self : in out Writer) is
   begin
      Self.Staged := 0;
      Self.Call_Ordinal := 0;
      Self.Root_Started := False;
      Self.Root_Complete := False;
      Self.Depth := 0;
      Self.Active_String := No_String;
      Self.String_Remaining := 0;
      Self.String_Written := 0;
      Self.UTF8_Lead := 0;
      Self.UTF8_Lead_Offset := 0;
      Self.UTF8_Have := 0;
      Self.UTF8_Need := 0;
      Errors.Clear (Self.Last_Diagnostic);
   end Clear_Transaction;

   procedure Apply_Profile
     (Self       : in out Writer;
      Profile    : Profiles.Writer_Profile;
      Diagnostic : out Errors.Diagnostic)
   is
      Status : constant Profiles.Profile_Status := Profiles.Validate (Profile);
   begin
      Clear_Transaction (Self);
      Self.Profile_Value := Profile;
      Self.Profile_Applied := Status = Profiles.Profile_Supported;
      case Status is
         when Profiles.Profile_Supported =>
            Self.Current_State := Ready;
            Errors.Clear (Diagnostic);
         when Profiles.Profile_Unsupported =>
            Self.Current_State := Failed;
            Set_Diagnostic
              (Diagnostic, Errors.Unsupported_Profile, Errors.No_Coordinate, 0);
            Self.Last_Diagnostic := Diagnostic;
         when Profiles.Profile_Incompatible =>
            Self.Current_State := Failed;
            Set_Diagnostic
              (Diagnostic, Errors.Incompatible_Profile, Errors.No_Coordinate, 0);
            Self.Last_Diagnostic := Diagnostic;
      end case;
   end Apply_Profile;

   procedure Initialize
     (Self       : in out Writer;
      Profile    : Profiles.Writer_Profile;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      if Self.Current_State /= Uninitialized then
         Set_Diagnostic
           (Diagnostic, Errors.Invalid_State, Errors.CBOR_Call_Ordinal, 0);
         return;
      end if;
      Apply_Profile (Self, Profile, Diagnostic);
   end Initialize;

   procedure Begin_Document
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic)
   is
      Status : Destinations.Begin_Status;
   begin
      if Self.Current_State /= Ready then
         Set_Diagnostic
           (Diagnostic, Errors.Invalid_State, Errors.CBOR_Call_Ordinal, Self.Call_Ordinal);
         return;
      end if;

      pragma Assert (not Self.Destination_Call_Active);
      Self.Destination_Call_Active := True;
      Destination_Begin (Target, Status);
      Self.Destination_Call_Active := False;
      if Status = Destinations.Begin_Succeeded then
         Self.Current_State := Active;
         Errors.Clear (Diagnostic);
      else
         Set_Diagnostic
           (Diagnostic, Errors.Destination_Failed, Errors.Staged_Output_Byte, 0);
         Self.Last_Diagnostic := Diagnostic;
         Self.Current_State := Failed;
      end if;
   end Begin_Document;

   procedure Abort_With_Primary
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : in out Errors.Diagnostic)
   is
      Status : Destinations.Abort_Status;
   begin
      pragma Assert (not Self.Destination_Call_Active);
      Self.Destination_Call_Active := True;
      Destination_Abort (Target, Status);
      Self.Destination_Call_Active := False;
      if Status = Destinations.Abort_Failed then
         if Diagnostic.Code = Errors.No_Error then
            Set_Diagnostic
              (Diagnostic,
               Errors.Abort_Failed,
               Errors.Staged_Output_Byte,
               Self.Staged);
         else
            Diagnostic.Secondary := Errors.Abort_Failed;
            Diagnostic.Secondary_Coordinate := Errors.Staged_Output_Byte;
            Diagnostic.Secondary_Offset := Self.Staged;
         end if;
      end if;
      Self.Last_Diagnostic := Diagnostic;
      Self.Current_State := Failed;
   end Abort_With_Primary;

   procedure Grammar_Failure
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Code       : Errors.Error_Code;
      Coordinate : Errors.Coordinate_Kind;
      Offset     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Set_Diagnostic (Diagnostic, Code, Coordinate, Offset);
      Abort_With_Primary (Self, Target, Diagnostic);
   end Grammar_Failure;

   function Active_Call
     (Self       : Writer;
      Diagnostic : out Errors.Diagnostic) return Boolean
   is
   begin
      pragma Assert (not Self.Destination_Call_Active);
      if Self.Current_State = Active then
         Errors.Clear (Diagnostic);
         return True;
      end if;

      Set_Diagnostic
        (Diagnostic,
         Errors.Invalid_State,
         Errors.CBOR_Call_Ordinal,
         Self.Call_Ordinal);
      return False;
   end Active_Call;

   function Semantic_Call
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic) return Boolean
   is
   begin
      if not Active_Call (Self, Diagnostic) then
         return False;
      elsif Self.Call_Ordinal = Interfaces.Unsigned_64'Last then
         Grammar_Failure
           (Self,
            Target,
            Errors.Offset_Exhausted,
            Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal,
            Diagnostic);
         return False;
      end if;
      return True;
   end Semantic_Call;

   function Can_Start_Value (Self : Writer) return Boolean is
   begin
      if Self.Active_String /= No_String or else Self.Root_Complete then
         return False;
      elsif Self.Depth = 0 then
         return not Self.Root_Started;
      end if;

      case Self.Stack (Self.Depth).Kind is
         when Array_Frame =>
            return Self.Stack (Self.Depth).Indefinite
              or else Self.Stack (Self.Depth).Remaining > 0;
         when Map_Frame =>
            return Self.Stack (Self.Depth).Indefinite
              or else Self.Stack (Self.Depth).Remaining > 0
              or else not Self.Stack (Self.Depth).Expecting_Key;
         when Tag_Frame =>
            return not Self.Stack (Self.Depth).Child_Done;
         when Indefinite_Byte_String_Frame | Indefinite_Text_String_Frame =>
            return False;
      end case;
   end Can_Start_Value;

   procedure Complete_Item (Self : in out Writer) is
   begin
      if Self.Depth = 0 then
         Self.Root_Started := True;
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
     (Self          : in out Writer;
      Kind          : Frame_Kind;
      Indefinite    : Boolean := False;
      Remaining     : Interfaces.Unsigned_64 := 0;
      Expecting_Key : Boolean := True) return Boolean
   is
   begin
      if Self.Depth = Self.Maximum_Syntax_Depth then
         return False;
      end if;

      Self.Depth := Self.Depth + 1;
      Self.Stack (Self.Depth) :=
        (Kind          => Kind,
         Indefinite    => Indefinite,
         Remaining     => Remaining,
         Expecting_Key => Expecting_Key,
         Child_Done    => False);
      Self.Root_Started := True;
      return True;
   end Push;

   procedure Write_Data
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Data       : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic;
      Success    : out Boolean)
   is
      Written : Ada.Streams.Stream_Element_Count;
      Status  : Destinations.Write_Status;
      Length  : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Data'Length);
   begin
      Success := False;
      if Length > Interfaces.Unsigned_64'Last - Self.Staged then
         Set_Diagnostic
           (Diagnostic,
            Errors.Offset_Exhausted,
            Errors.Staged_Output_Byte,
            Self.Staged);
         Abort_With_Primary (Self, Target, Diagnostic);
         return;
      end if;

      pragma Assert (not Self.Destination_Call_Active);
      Self.Destination_Call_Active := True;
      Destination_Write (Target, Data, Written, Status);
      Self.Destination_Call_Active := False;
      Self.Staged := Self.Staged + Interfaces.Unsigned_64 (Written);
      case Status is
         when Destinations.Write_Succeeded =>
            Errors.Clear (Diagnostic);
            Success := True;
         when Destinations.Write_Exhausted =>
            Set_Diagnostic
              (Diagnostic,
               Errors.Destination_Exhausted,
               Errors.Staged_Output_Byte,
               Self.Staged);
            Abort_With_Primary (Self, Target, Diagnostic);
         when Destinations.Write_Failed =>
            Set_Diagnostic
              (Diagnostic,
               Errors.Destination_Failed,
               Errors.Staged_Output_Byte,
               Self.Staged);
            Abort_With_Primary (Self, Target, Diagnostic);
      end case;
   end Write_Data;

   procedure Succeed_Call (Self : in out Writer; Diagnostic : out Errors.Diagnostic) is
   begin
      Self.Call_Ordinal := Self.Call_Ordinal + 1;
      Errors.Clear (Diagnostic);
   end Succeed_Call;

   procedure Write_Head
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Major      : Natural;
      Argument   : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic;
      Success    : out Boolean)
   is
      Data   : Ada.Streams.Stream_Element_Array (1 .. 9) := [others => 0];
      Length : Ada.Streams.Stream_Element_Offset;
      Value  : Interfaces.Unsigned_64 := Argument;
   begin
      if Argument < 24 then
         Length := 1;
         Data (1) := Ada.Streams.Stream_Element (Major * 32 + Natural (Argument));
      elsif Argument <= 16#FF# then
         Length := 2;
         Data (1) := Ada.Streams.Stream_Element (Major * 32 + 24);
      elsif Argument <= 16#FFFF# then
         Length := 3;
         Data (1) := Ada.Streams.Stream_Element (Major * 32 + 25);
      elsif Argument <= 16#FFFF_FFFF# then
         Length := 5;
         Data (1) := Ada.Streams.Stream_Element (Major * 32 + 26);
      else
         Length := 9;
         Data (1) := Ada.Streams.Stream_Element (Major * 32 + 27);
      end if;

      for Index in reverse 2 .. Length loop
         Data (Index) := Ada.Streams.Stream_Element (Value and 16#FF#);
         Value := Interfaces.Shift_Right (Value, 8);
      end loop;
      Write_Data (Self, Target, Data (1 .. Length), Diagnostic, Success);
   end Write_Head;

   procedure Write_Indefinite
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Major      : Natural;
      Diagnostic : out Errors.Diagnostic;
      Success    : out Boolean)
   is
      Data : constant Ada.Streams.Stream_Element_Array (1 .. 1) :=
        [1 => Ada.Streams.Stream_Element (Major * 32 + 31)];
   begin
      Write_Data (Self, Target, Data, Diagnostic, Success);
   end Write_Indefinite;

   procedure Put_Head_Value
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Major      : Natural;
      Argument   : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
      Success : Boolean;
   begin
      if not Semantic_Call (Self, Target, Diagnostic) then
         return;
      elsif not Can_Start_Value (Self) then
         Grammar_Failure
           (Self,
            Target,
            Errors.Invalid_Writer_Grammar,
            Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal,
            Diagnostic);
         return;
      elsif Self.Call_Ordinal = Interfaces.Unsigned_64'Last then
         Grammar_Failure
           (Self,
            Target,
            Errors.Offset_Exhausted,
            Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal,
            Diagnostic);
         return;
      end if;

      Write_Head (Self, Target, Major, Argument, Diagnostic, Success);
      if Success then
         Self.Root_Started := True;
         Complete_Item (Self);
         Succeed_Call (Self, Diagnostic);
      end if;
   end Put_Head_Value;

   procedure Put_Unsigned
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Put_Head_Value (Self, Target, 0, Value, Diagnostic);
   end Put_Unsigned;

   procedure Put_Negative_Argument
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Argument   : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Put_Head_Value (Self, Target, 1, Argument, Diagnostic);
   end Put_Negative_Argument;

   procedure Put_Signed
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Interfaces.Integer_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      if Value >= 0 then
         Put_Unsigned (Self, Target, Interfaces.Unsigned_64 (Value), Diagnostic);
      else
         Put_Negative_Argument
           (Self,
            Target,
            Interfaces.Unsigned_64 (-(Value + 1)),
            Diagnostic);
      end if;
   end Put_Signed;

   procedure Put_False
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Put_Head_Value (Self, Target, 7, 20, Diagnostic);
   end Put_False;

   procedure Put_True
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Put_Head_Value (Self, Target, 7, 21, Diagnostic);
   end Put_True;

   procedure Put_Null
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Put_Head_Value (Self, Target, 7, 22, Diagnostic);
   end Put_Null;

   procedure Put_Undefined
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Put_Head_Value (Self, Target, 7, 23, Diagnostic);
   end Put_Undefined;

   procedure Put_Simple
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Values.Simple_Code;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      if not Semantic_Call (Self, Target, Diagnostic) then
         return;
      elsif Natural (Value) in 20 .. 31 then
         Grammar_Failure
           (Self,
            Target,
            Errors.Invalid_Simple_Value,
            Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal,
            Diagnostic);
      else
         Put_Head_Value (Self, Target, 7, Interfaces.Unsigned_64 (Value), Diagnostic);
      end if;
   end Put_Simple;

   procedure Put_Float
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Values.Float_Value;
      Diagnostic : out Errors.Diagnostic)
   is
      Data    : Ada.Streams.Stream_Element_Array (1 .. 9) := [others => 0];
      Length  : Ada.Streams.Stream_Element_Offset;
      Payload : Interfaces.Unsigned_64 := Values.Bits (Value);
      Success : Boolean;
   begin
      if not Semantic_Call (Self, Target, Diagnostic) then
         return;
      elsif not Can_Start_Value (Self) then
         Grammar_Failure
           (Self,
            Target,
            Errors.Invalid_Writer_Grammar,
            Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal,
            Diagnostic);
         return;
      end if;

      case Values.Width (Value) is
         when Values.Binary16 =>
            Length := 3;
            Data (1) := 16#F9#;
         when Values.Binary32 =>
            Length := 5;
            Data (1) := 16#FA#;
         when Values.Binary64 =>
            Length := 9;
            Data (1) := 16#FB#;
      end case;
      for Index in reverse 2 .. Length loop
         Data (Index) := Ada.Streams.Stream_Element (Payload and 16#FF#);
         Payload := Interfaces.Shift_Right (Payload, 8);
      end loop;

      Write_Data (Self, Target, Data (1 .. Length), Diagnostic, Success);
      if Success then
         Self.Root_Started := True;
         Complete_Item (Self);
         Succeed_Call (Self, Diagnostic);
      end if;
   end Put_Float;

   procedure Begin_Definite_String
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Major      : Natural;
      Length     : Interfaces.Unsigned_64;
      Mode       : String_Mode;
      Diagnostic : out Errors.Diagnostic)
   is
      Success : Boolean;
   begin
      if not Semantic_Call (Self, Target, Diagnostic) then
         return;
      elsif not Can_Start_Value (Self) then
         Grammar_Failure
           (Self, Target, Errors.Invalid_Writer_Grammar, Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal, Diagnostic);
         return;
      end if;
      Write_Head (Self, Target, Major, Length, Diagnostic, Success);
      if Success then
         Self.Root_Started := True;
         Self.Active_String := Mode;
         Self.String_Remaining := Length;
         Self.String_Written := 0;
         Self.UTF8_Have := 0;
         Self.UTF8_Need := 0;
         Succeed_Call (Self, Diagnostic);
      end if;
   end Begin_Definite_String;

   procedure Begin_Byte_String
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Begin_Definite_String
        (Self, Target, 2, Length, Definite_Byte_String, Diagnostic);
   end Begin_Byte_String;

   procedure Begin_Text_String
     (Self         : in out Writer;
      Target       : in out Destination_Type;
      Octet_Length : Interfaces.Unsigned_64;
      Diagnostic   : out Errors.Diagnostic)
   is
   begin
      Begin_Definite_String
        (Self, Target, 3, Octet_Length, Definite_Text_String, Diagnostic);
   end Begin_Text_String;

   procedure Begin_Indefinite_String
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Major      : Natural;
      Kind       : Frame_Kind;
      Diagnostic : out Errors.Diagnostic)
   is
      Success : Boolean;
   begin
      if not Semantic_Call (Self, Target, Diagnostic) then
         return;
      elsif not Can_Start_Value (Self) then
         Grammar_Failure
           (Self, Target, Errors.Invalid_Writer_Grammar, Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal, Diagnostic);
         return;
      elsif Self.Depth = Self.Maximum_Syntax_Depth then
         Grammar_Failure
           (Self, Target, Errors.Depth_Exhausted, Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal, Diagnostic);
         return;
      end if;

      Write_Indefinite (Self, Target, Major, Diagnostic, Success);
      if Success then
         if not Push (Self, Kind, True) then
            raise Program_Error;
         end if;
         Succeed_Call (Self, Diagnostic);
      end if;
   end Begin_Indefinite_String;

   procedure Begin_Indefinite_Byte_String
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Begin_Indefinite_String
        (Self, Target, 2, Indefinite_Byte_String_Frame, Diagnostic);
   end Begin_Indefinite_Byte_String;

   procedure Begin_Indefinite_Text_String
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Begin_Indefinite_String
        (Self, Target, 3, Indefinite_Text_String_Frame, Diagnostic);
   end Begin_Indefinite_Text_String;

   procedure Begin_String_Chunk
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Major      : Natural;
      Length     : Interfaces.Unsigned_64;
      Mode       : String_Mode;
      Frame      : Frame_Kind;
      Diagnostic : out Errors.Diagnostic)
   is
      Success : Boolean;
   begin
      if not Semantic_Call (Self, Target, Diagnostic) then
         return;
      elsif Self.Active_String /= No_String
        or else Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Frame
      then
         Grammar_Failure
           (Self, Target, Errors.Invalid_Writer_Grammar, Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal, Diagnostic);
         return;
      end if;

      Write_Head (Self, Target, Major, Length, Diagnostic, Success);
      if Success then
         Self.Active_String := Mode;
         Self.String_Remaining := Length;
         Self.String_Written := 0;
         Self.UTF8_Have := 0;
         Self.UTF8_Need := 0;
         Succeed_Call (Self, Diagnostic);
      end if;
   end Begin_String_Chunk;

   procedure Begin_Byte_String_Chunk
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Begin_String_Chunk
        (Self, Target, 2, Length, Byte_String_Chunk,
         Indefinite_Byte_String_Frame, Diagnostic);
   end Begin_Byte_String_Chunk;

   procedure Begin_Text_String_Chunk
     (Self         : in out Writer;
      Target       : in out Destination_Type;
      Octet_Length : Interfaces.Unsigned_64;
      Diagnostic   : out Errors.Diagnostic)
   is
   begin
      Begin_String_Chunk
        (Self, Target, 3, Octet_Length, Text_String_Chunk,
         Indefinite_Text_String_Frame, Diagnostic);
   end Begin_Text_String_Chunk;

   procedure Put_Byte_String_Fragment
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic)
   is
      Length  : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Value'Length);
      Success : Boolean;
   begin
      if not Semantic_Call (Self, Target, Diagnostic) then
         return;
      elsif Self.Active_String not in Definite_Byte_String | Byte_String_Chunk then
         Grammar_Failure
           (Self, Target, Errors.Invalid_Writer_Grammar, Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal, Diagnostic);
         return;
      elsif Length > Self.String_Remaining then
         Grammar_Failure
           (Self, Target, Errors.Invalid_String_Length, Errors.Writer_Token_Byte,
            Self.String_Written + Self.String_Remaining, Diagnostic);
         return;
      end if;

      Write_Data (Self, Target, Value, Diagnostic, Success);
      if Success then
         Self.String_Remaining := Self.String_Remaining - Length;
         Self.String_Written := Self.String_Written + Length;
         Succeed_Call (Self, Diagnostic);
      end if;
   end Put_Byte_String_Fragment;

   procedure Put_Text_String_Fragment
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic)
   is
      Length     : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Value'Length);
      Local_Have : Natural := Self.UTF8_Have;
      Local_Need : Natural := Self.UTF8_Need;
      Local_Lead : Ada.Streams.Stream_Element := Self.UTF8_Lead;
      Local_Lead_Offset : Interfaces.Unsigned_64 := Self.UTF8_Lead_Offset;
      Position   : Interfaces.Unsigned_64 := Self.String_Written;
      Success    : Boolean;

      function Needed (Octet : Ada.Streams.Stream_Element) return Natural is
         Number : constant Natural := Natural (Octet);
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
      end Needed;

      function Continuation_Valid
        (Lead : Ada.Streams.Stream_Element;
         Have : Natural;
         Octet : Ada.Streams.Stream_Element) return Boolean
      is
         Number : constant Natural := Natural (Octet);
      begin
         if Have /= 1 then
            return Number in 16#80# .. 16#BF#;
         end if;
         case Natural (Lead) is
            when 16#E0# => return Number in 16#A0# .. 16#BF#;
            when 16#ED# => return Number in 16#80# .. 16#9F#;
            when 16#F0# => return Number in 16#90# .. 16#BF#;
            when 16#F4# => return Number in 16#80# .. 16#8F#;
            when others => return Number in 16#80# .. 16#BF#;
         end case;
      end Continuation_Valid;
   begin
      if not Semantic_Call (Self, Target, Diagnostic) then
         return;
      elsif Self.Active_String not in Definite_Text_String | Text_String_Chunk then
         Grammar_Failure
           (Self, Target, Errors.Invalid_Writer_Grammar, Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal, Diagnostic);
         return;
      elsif Length > Self.String_Remaining then
         Grammar_Failure
           (Self, Target, Errors.Invalid_String_Length, Errors.Writer_Token_Byte,
            Self.String_Written + Self.String_Remaining, Diagnostic);
         return;
      end if;

      for Octet of Value loop
         if Local_Need = 0 then
            Local_Need := Needed (Octet);
            if Local_Need = 0 then
               Grammar_Failure
                 (Self, Target, Errors.Invalid_UTF8, Errors.Writer_Token_Byte,
                  Position, Diagnostic);
               return;
            elsif Local_Need = 1 then
               Local_Need := 0;
               Local_Have := 0;
            else
               Local_Lead := Octet;
               Local_Lead_Offset := Position;
               Local_Have := 1;
            end if;
         elsif not Continuation_Valid (Local_Lead, Local_Have, Octet) then
            Grammar_Failure
              (Self, Target, Errors.Invalid_UTF8, Errors.Writer_Token_Byte,
               Position, Diagnostic);
            return;
         else
            Local_Have := Local_Have + 1;
            if Local_Have = Local_Need then
               Local_Have := 0;
               Local_Need := 0;
            end if;
         end if;
         Position := Position + 1;
      end loop;

      Write_Data (Self, Target, Value, Diagnostic, Success);
      if Success then
         Self.String_Remaining := Self.String_Remaining - Length;
         Self.String_Written := Position;
         Self.UTF8_Have := Local_Have;
         Self.UTF8_Need := Local_Need;
         Self.UTF8_Lead := Local_Lead;
         Self.UTF8_Lead_Offset := Local_Lead_Offset;
         Succeed_Call (Self, Diagnostic);
      end if;
   end Put_Text_String_Fragment;

   procedure End_String_Part
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Expected   : String_Mode;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      if not Semantic_Call (Self, Target, Diagnostic) then
         return;
      elsif Self.Active_String /= Expected then
         Grammar_Failure
           (Self, Target, Errors.Invalid_Writer_Grammar, Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal, Diagnostic);
      elsif Self.String_Remaining /= 0 then
         Grammar_Failure
           (Self, Target, Errors.Invalid_String_Length, Errors.Writer_Token_Byte,
            Self.String_Written, Diagnostic);
      elsif Self.UTF8_Need /= 0 then
         Grammar_Failure
           (Self, Target, Errors.Invalid_UTF8, Errors.Writer_Token_Byte,
            Self.String_Written, Diagnostic);
      else
         Self.Active_String := No_String;
         Self.UTF8_Have := 0;
         Self.UTF8_Need := 0;
         Succeed_Call (Self, Diagnostic);
      end if;
   end End_String_Part;

   procedure End_Byte_String_Chunk
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      End_String_Part (Self, Target, Byte_String_Chunk, Diagnostic);
   end End_Byte_String_Chunk;

   procedure End_Text_String_Chunk
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      End_String_Part (Self, Target, Text_String_Chunk, Diagnostic);
   end End_Text_String_Chunk;

   procedure End_String
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Definite   : String_Mode;
      Indefinite : Frame_Kind;
      Diagnostic : out Errors.Diagnostic)
   is
      Success : Boolean;
      Break   : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 16#FF#];
   begin
      if not Semantic_Call (Self, Target, Diagnostic) then
         return;
      elsif Self.Active_String = Definite then
         if Self.String_Remaining /= 0 then
            Grammar_Failure
              (Self, Target, Errors.Invalid_String_Length, Errors.Writer_Token_Byte,
               Self.String_Written, Diagnostic);
         elsif Self.UTF8_Need /= 0 then
            Grammar_Failure
              (Self, Target, Errors.Invalid_UTF8, Errors.Writer_Token_Byte,
               Self.String_Written, Diagnostic);
         else
            Self.Active_String := No_String;
            Complete_Item (Self);
            Succeed_Call (Self, Diagnostic);
         end if;
      elsif Self.Active_String = No_String
        and then Self.Depth > 0
        and then Self.Stack (Self.Depth).Kind = Indefinite
      then
         Write_Data (Self, Target, Break, Diagnostic, Success);
         if Success then
            Self.Depth := Self.Depth - 1;
            Complete_Item (Self);
            Succeed_Call (Self, Diagnostic);
         end if;
      else
         Grammar_Failure
           (Self, Target, Errors.Invalid_Writer_Grammar, Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal, Diagnostic);
      end if;
   end End_String;

   procedure End_Byte_String
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      End_String
        (Self, Target, Definite_Byte_String, Indefinite_Byte_String_Frame, Diagnostic);
   end End_Byte_String;

   procedure End_Text_String
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      End_String
        (Self, Target, Definite_Text_String, Indefinite_Text_String_Frame, Diagnostic);
   end End_Text_String;

   procedure Begin_Container
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Major      : Natural;
      Kind       : Frame_Kind;
      Indefinite : Boolean;
      Remaining  : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
      Success : Boolean;
   begin
      if not Semantic_Call (Self, Target, Diagnostic) then
         return;
      elsif not Can_Start_Value (Self) then
         Grammar_Failure
           (Self, Target, Errors.Invalid_Writer_Grammar, Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal, Diagnostic);
         return;
      elsif Self.Depth = Self.Maximum_Syntax_Depth then
         Grammar_Failure
           (Self, Target, Errors.Depth_Exhausted, Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal, Diagnostic);
         return;
      end if;

      if Indefinite then
         Write_Indefinite (Self, Target, Major, Diagnostic, Success);
      else
         Write_Head (Self, Target, Major, Remaining, Diagnostic, Success);
      end if;
      if Success then
         if not Push (Self, Kind, Indefinite, Remaining, True) then
            raise Program_Error;
         end if;
         Succeed_Call (Self, Diagnostic);
      end if;
   end Begin_Container;

   procedure Begin_Array
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Begin_Container (Self, Target, 4, Array_Frame, False, Length, Diagnostic);
   end Begin_Array;

   procedure Begin_Indefinite_Array
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Begin_Container (Self, Target, 4, Array_Frame, True, 0, Diagnostic);
   end Begin_Indefinite_Array;

   procedure Begin_Map
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Pair_Count : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      Begin_Container (Self, Target, 5, Map_Frame, False, Pair_Count, Diagnostic);
   end Begin_Map;

   procedure Begin_Indefinite_Map
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      Begin_Container (Self, Target, 5, Map_Frame, True, 0, Diagnostic);
   end Begin_Indefinite_Map;

   procedure End_Container
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Kind       : Frame_Kind;
      Diagnostic : out Errors.Diagnostic)
   is
      Success : Boolean := True;
      Break   : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 16#FF#];
   begin
      if not Semantic_Call (Self, Target, Diagnostic) then
         return;
      elsif Self.Active_String /= No_String
        or else Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Kind
        or else (not Self.Stack (Self.Depth).Indefinite
                 and then Self.Stack (Self.Depth).Remaining /= 0)
        or else (Kind = Map_Frame and then not Self.Stack (Self.Depth).Expecting_Key)
      then
         Grammar_Failure
           (Self, Target, Errors.Invalid_Writer_Grammar, Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal, Diagnostic);
         return;
      end if;

      if Self.Stack (Self.Depth).Indefinite then
         Write_Data (Self, Target, Break, Diagnostic, Success);
      end if;
      if Success then
         Self.Depth := Self.Depth - 1;
         Complete_Item (Self);
         Succeed_Call (Self, Diagnostic);
      end if;
   end End_Container;

   procedure End_Array
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      End_Container (Self, Target, Array_Frame, Diagnostic);
   end End_Array;

   procedure End_Map
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      End_Container (Self, Target, Map_Frame, Diagnostic);
   end End_Map;

   procedure Begin_Tag
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Number     : Values.Tag_Number;
      Diagnostic : out Errors.Diagnostic)
   is
      Success : Boolean;
   begin
      if not Semantic_Call (Self, Target, Diagnostic) then
         return;
      elsif not Can_Start_Value (Self) then
         Grammar_Failure
           (Self, Target, Errors.Invalid_Writer_Grammar, Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal, Diagnostic);
         return;
      elsif Self.Depth = Self.Maximum_Syntax_Depth then
         Grammar_Failure
           (Self, Target, Errors.Depth_Exhausted, Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal, Diagnostic);
         return;
      end if;

      Write_Head (Self, Target, 6, Number, Diagnostic, Success);
      if Success then
         if not Push (Self, Tag_Frame) then
            raise Program_Error;
         end if;
         Succeed_Call (Self, Diagnostic);
      end if;
   end Begin_Tag;

   procedure End_Tag
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
   begin
      if not Semantic_Call (Self, Target, Diagnostic) then
         return;
      elsif Self.Active_String /= No_String
        or else Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Tag_Frame
        or else not Self.Stack (Self.Depth).Child_Done
      then
         Grammar_Failure
           (Self, Target, Errors.Invalid_Writer_Grammar, Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal, Diagnostic);
      else
         Self.Depth := Self.Depth - 1;
         Complete_Item (Self);
         Succeed_Call (Self, Diagnostic);
      end if;
   end End_Tag;

   procedure Finish_Document
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
      Commit_Status : Destinations.Commit_Status;
   begin
      if not Active_Call (Self, Diagnostic) then
         return;
      elsif not Self.Root_Complete
        or else Self.Depth /= 0
        or else Self.Active_String /= No_String
      then
         Grammar_Failure
           (Self, Target, Errors.Invalid_Writer_Grammar, Errors.CBOR_Call_Ordinal,
            Self.Call_Ordinal, Diagnostic);
         return;
      end if;

      pragma Assert (not Self.Destination_Call_Active);
      Self.Destination_Call_Active := True;
      Destination_Commit (Target, Commit_Status);
      Self.Destination_Call_Active := False;
      if Commit_Status = Destinations.Commit_Succeeded then
         Self.Current_State := Completed;
         Errors.Clear (Diagnostic);
      else
         Set_Diagnostic
           (Diagnostic, Errors.Commit_Failed, Errors.Staged_Output_Byte, Self.Staged);
         Abort_With_Primary (Self, Target, Diagnostic);
      end if;
   end Finish_Document;

   procedure Abort_Document
     (Self : in out Writer; Target : in out Destination_Type; Diagnostic : out Errors.Diagnostic)
   is
      Status : Destinations.Abort_Status;
   begin
      case Self.Current_State is
         when Ready =>
            Self.Current_State := Aborted;
            Errors.Clear (Diagnostic);
            Errors.Clear (Self.Last_Diagnostic);
         when Active =>
            pragma Assert (not Self.Destination_Call_Active);
            Self.Destination_Call_Active := True;
            Destination_Abort (Target, Status);
            Self.Destination_Call_Active := False;
            if Status = Destinations.Abort_Succeeded then
               Self.Current_State := Aborted;
               Errors.Clear (Diagnostic);
               Errors.Clear (Self.Last_Diagnostic);
            else
               Set_Diagnostic
                 (Diagnostic,
                  Errors.Abort_Failed,
                  Errors.Staged_Output_Byte,
                  Self.Staged);
               Self.Last_Diagnostic := Diagnostic;
               Self.Current_State := Failed;
            end if;
         when Aborted =>
            Errors.Clear (Diagnostic);
         when Uninitialized | Completed | Failed =>
            Set_Diagnostic
              (Diagnostic, Errors.Invalid_State, Errors.CBOR_Call_Ordinal, Self.Call_Ordinal);
      end case;
   end Abort_Document;

   procedure Reset
     (Self       : in out Writer;
      Profile    : Profiles.Writer_Profile;
      Diagnostic : out Errors.Diagnostic)
   is
   begin
      if Self.Current_State not in Completed | Failed | Aborted then
         Set_Diagnostic
           (Diagnostic, Errors.Invalid_State, Errors.CBOR_Call_Ordinal, Self.Call_Ordinal);
         return;
      end if;
      Apply_Profile (Self, Profile, Diagnostic);
   end Reset;

   function State (Self : Writer) return Writer_State is
     (Self.Current_State);

   function Has_Applied_Profile (Self : Writer) return Boolean is
     (Self.Profile_Applied);

   function Applied_Profile (Self : Writer) return Profiles.Writer_Profile is
     (Self.Profile_Value);

   function Terminal_Diagnostic (Self : Writer) return Errors.Diagnostic is
     (Self.Last_Diagnostic);

   function Staged_Length (Self : Writer) return Interfaces.Unsigned_64 is
     (Self.Staged);

end Flyology_CBOR.Writer_Engine;
