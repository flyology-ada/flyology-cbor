with Ada.Streams;
with Flyology_CBOR.Errors;
with Flyology_CBOR.Profiles;
with Flyology_CBOR.Values;

package Flyology_CBOR.Parsing is
   --  Parser is single-owner and not task-safe. Concurrent access or task abort during a call is
   --  outside the contract. The parser allocates nothing and retains no input-array reference.
   subtype Byte_Offset is Errors.Byte_Offset;

   type Parser_State is
     (Uninitialized,
      Ready,
      Active,
      Failure_Pending,
      Completed,
      Failed,
      Aborted);

   type Event_Kind is
     (Document_Begin,
      Document_End,
      Unsigned_Value,
      Negative_Integer_Value,
      Byte_String_Begin,
      Byte_String_Chunk_Begin,
      Byte_String_Fragment,
      Byte_String_Chunk_End,
      Byte_String_End,
      Text_String_Begin,
      Text_String_Chunk_Begin,
      Text_String_Fragment,
      Text_String_Chunk_End,
      Text_String_End,
      Array_Begin,
      Array_End,
      Map_Begin,
      Map_End,
      Tag_Begin,
      Tag_End,
      False_Value,
      True_Value,
      Null_Value,
      Undefined_Value,
      Simple_Value,
      Float_Value);

   type Source_Range is record
      First        : Byte_Offset;
      Octet_Length : Byte_Offset;
   end record;

   type Chunk_Range is record
      First_Count  : Ada.Streams.Stream_Element_Count;
      Octet_Length : Ada.Streams.Stream_Element_Count;
   end record;

   subtype Scalar_Octets is
     Ada.Streams.Stream_Element_Array
       (Ada.Streams.Stream_Element_Offset range 1 .. 4);

   type Inline_Scalar is record
      Length : Positive range 1 .. 4;
      Octets : Scalar_Octets;
   end record;

   type Fragment_Representation is (Borrowed_Input, Inline_Text_Scalar);

   type Event is private;

   type Event_Array is
     array (Ada.Streams.Stream_Element_Offset range <>) of Event;

   --  Source is the complete absolute lexical range. Document_Begin and Document_End are
   --  zero-width at the operation origin/current end. Definite container, tag, string, and chunk
   --  ends are zero-width at the byte after their content. Indefinite array/map/string ends carry
   --  the break byte. Scalar and begin events carry their complete head; a head split across calls
   --  has no raw slice. Fragment events carry payload source only.
   function Kind (Item : Event) return Event_Kind;
   function Source (Item : Event) return Source_Range;
   function Has_Raw_Slice (Item : Event) return Boolean;

   type Slice_Status is
     (Slice_Resolved, No_Raw_Slice, Range_Outside_Window);

   procedure Resolve_Raw_Range
     (Item          : Event;
      Window_Origin : Byte_Offset;
      Window_Length : Ada.Streams.Stream_Element_Count;
      Slice         : out Chunk_Range;
      Status        : out Slice_Status);

   --  Slice resolution authenticates coordinates only. Slice_Resolved is usable only with the
   --  exact unchanged Input actual from the Step or Drain call that returned Item. The coordinate
   --  borrow remains eligible until the caller mutates, reuses, or releases that producing actual;
   --  a later parser call alone does not invalidate it. Byte fragments are always Borrowed_Input.
   --  A text fragment is Borrowed_Input or one owned Inline_Text_Scalar assembled from fixed carry.

   function Declared_Length (Item : Event) return Values.Item_Length
   with
     Pre =>
       Kind (Item)
       in Byte_String_Begin
        | Byte_String_Chunk_Begin
        | Text_String_Begin
        | Text_String_Chunk_Begin
        | Array_Begin
        | Map_Begin;

   function Integer_Data (Item : Event) return Values.Integer_Value
   with Pre => Kind (Item) in Unsigned_Value | Negative_Integer_Value;

   function Tag_Data (Item : Event) return Values.Tag_Number
   with Pre => Kind (Item) = Tag_Begin;

   function Simple_Data (Item : Event) return Values.Simple_Code
   with Pre => Kind (Item) = Simple_Value;

   function Float_Data (Item : Event) return Values.Float_Value
   with Pre => Kind (Item) = Float_Value;

   function Fragment_Kind
     (Item : Event) return Fragment_Representation
   with Pre => Kind (Item) in Byte_String_Fragment | Text_String_Fragment;

   function Fragment_Source (Item : Event) return Source_Range
   with Pre => Kind (Item) in Byte_String_Fragment | Text_String_Fragment;

   function Inline_Text (Item : Event) return Inline_Scalar
   with
     Pre =>
       Kind (Item) = Text_String_Fragment
       and then Fragment_Kind (Item) = Inline_Text_Scalar;

   type Step_Outcome is
     (Event_Ready,
      Need_Input,
      Document_Complete,
      Step_Failed,
      Call_Rejected);

   type Step_Result is record
      Outcome      : Step_Outcome;
      Input_Origin : Byte_Offset;
      Consumed     : Ada.Streams.Stream_Element_Count;
      Item         : Event;
      Diagnostic   : Errors.Diagnostic;
   end record;

   --  Input_Origin and Consumed are eligible for every outcome. Item is eligible only for
   --  Event_Ready. Diagnostic is eligible only for Step_Failed or Call_Rejected. Need_Input
   --  consumes all supplied input; a rejected call consumes zero. In other outcomes Diagnostic is
   --  cleared.

   type Drain_Stop is
     (Output_Full,
      Drain_Need_Input,
      Drain_Document_Complete,
      Drain_Failed,
      Drain_Rejected);

   type Drain_Result is record
      Stop         : Drain_Stop;
      Input_Origin : Byte_Offset;
      Consumed     : Ada.Streams.Stream_Element_Count;
      Produced     : Ada.Streams.Stream_Element_Count;
      Diagnostic   : Errors.Diagnostic;
   end record;

   --  Input_Origin, Consumed, and Produced are eligible for every stop. Diagnostic is eligible
   --  only for Drain_Failed or Drain_Rejected and is otherwise cleared. Exactly the first
   --  Produced Events are eligible;
   --  every suffix component is unchanged. A null Events array returns Output_Full without effect.

   type Parser (Maximum_Syntax_Depth : Natural) is limited private;

   --  Initialize maps Uninitialized to Ready or Failed before byte zero. Step/Drain admit Ready,
   --  Active, and Failure_Pending. A pending failure reports with zero new publication and enters
   --  Failed. Document_Complete alone enters Completed. Abort maps Ready/Active to clean Aborted,
   --  Failure_Pending to Failed, and is idempotent in terminal states. Reset admits
   --  Failure_Pending, Completed, Failed, or Aborted and revalidates the complete profile.

   procedure Initialize
     (Self       : in out Parser;
      Profile    : Profiles.Parser_Profile;
      Diagnostic : out Errors.Diagnostic);

   procedure Step
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Result       : out Step_Result);

   procedure Drain
     (Self         : in out Parser;
      Input        : Ada.Streams.Stream_Element_Array;
      End_Of_Input : Boolean;
      Events       : in out Event_Array;
      Result       : out Drain_Result);

   procedure Abort_Document (Self : in out Parser);

   procedure Reset
     (Self       : in out Parser;
      Profile    : Profiles.Parser_Profile;
      Diagnostic : out Errors.Diagnostic);

   function State (Self : Parser) return Parser_State;
   function Has_Applied_Profile (Self : Parser) return Boolean;

   function Applied_Profile (Self : Parser) return Profiles.Parser_Profile
   with Pre => Has_Applied_Profile (Self);

   function Terminal_Diagnostic (Self : Parser) return Errors.Diagnostic
   with Pre => State (Self) in Failure_Pending | Failed | Aborted;

private
   type Event is record
      Event_Kind_Value : Event_Kind := Document_Begin;
      Source_Value     : Source_Range := (First => 0, Octet_Length => 0);
      Raw_Slice_Value  : Boolean := False;
      Length_Value     : Values.Item_Length := Values.Indefinite;
      Integer_Value    : Values.Integer_Value := Values.Unsigned (0);
      Tag_Value        : Values.Tag_Number := 0;
      Simple_Value     : Values.Simple_Code := 0;
      Float_Value_Data : Values.Float_Value;
      Fragment_Value   : Fragment_Representation := Borrowed_Input;
      Fragment_Range   : Source_Range := (First => 0, Octet_Length => 0);
      Inline_Value     : Inline_Scalar := (Length => 1, Octets => [others => 0]);
   end record;

   type Frame_Kind is
     (Array_Frame,
      Map_Frame,
      Tag_Frame,
      Indefinite_Byte_String_Frame,
      Indefinite_Text_String_Frame);

   type Syntax_Frame is record
      Kind          : Frame_Kind := Array_Frame;
      Indefinite    : Boolean := False;
      Remaining     : Values.Argument := 0;
      Expecting_Key : Boolean := True;
      Child_Done    : Boolean := False;
   end record;

   type Frame_Array is array (Natural range <>) of Syntax_Frame;

   type String_Mode is
     (No_String,
      Definite_Byte_String,
      Definite_Text_String,
      Byte_String_Chunk,
      Text_String_Chunk);

   subtype Header_Index is Positive range 1 .. 9;
   type Header_Buffer is array (Header_Index) of Ada.Streams.Stream_Element;

   type Parser (Maximum_Syntax_Depth : Natural) is limited record
      Current_State       : Parser_State := Uninitialized;
      Profile_Applied     : Boolean := False;
      Profile_Value       : Profiles.Parser_Profile;
      Last_Diagnostic     : Errors.Diagnostic;
      Current_Offset      : Byte_Offset := 0;
      Final_Latched       : Boolean := False;
      Document_Started    : Boolean := False;
      Root_Complete       : Boolean := False;
      Document_End_Sent   : Boolean := False;
      Depth               : Natural := 0;
      Stack               : Frame_Array (1 .. Maximum_Syntax_Depth);
      Active_String       : String_Mode := No_String;
      String_Remaining    : Values.Argument := 0;
      String_Payload_First : Byte_Offset := 0;
      Header              : Header_Buffer := [others => 0];
      Header_Have         : Natural range 0 .. 9 := 0;
      Header_Need         : Natural range 0 .. 9 := 0;
      Header_Start        : Byte_Offset := 0;
      Header_Was_Split    : Boolean := False;
      Text_Carry          : Scalar_Octets := [others => 0];
      Text_Carry_Length   : Natural range 0 .. 4 := 0;
      Text_Carry_Need     : Natural range 0 .. 4 := 0;
      Text_Carry_Start    : Byte_Offset := 0;
   end record;
end Flyology_CBOR.Parsing;
