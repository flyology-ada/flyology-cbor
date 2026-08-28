with Interfaces;

package Flyology_CBOR.Errors
  with Pure
is
   subtype Byte_Offset is Interfaces.Unsigned_64;

   type Error_Code is
     (No_Error,
      Unsupported_Profile,
      Incompatible_Profile,
      Invalid_State,
      Final_Input_Retracted,
      Unexpected_Initial_Byte,
      Reserved_Additional_Information,
      Invalid_Indefinite_Item,
      Invalid_String_Chunk,
      Invalid_UTF8,
      Unexpected_Break,
      Odd_Map,
      Truncated_Input,
      Trailing_Input,
      Depth_Exhausted,
      Offset_Exhausted,
      Invalid_Writer_Grammar,
      Invalid_String_Length,
      Invalid_Simple_Value,
      Destination_Exhausted,
      Destination_Failed,
      Commit_Failed,
      Abort_Failed);

   type Coordinate_Kind is
     (No_Coordinate,
      Source_Byte,
      Writer_Token_Byte,
      Staged_Output_Byte,
      CBOR_Call_Ordinal);

   type Diagnostic is record
      Code                 : Error_Code;
      Coordinate           : Coordinate_Kind;
      Offset               : Byte_Offset;
      Has_Construct_Offset : Boolean;
      Construct_Offset     : Byte_Offset;
      Secondary            : Error_Code;
      Secondary_Coordinate : Coordinate_Kind;
      Secondary_Offset     : Byte_Offset;
   end record;
   --  Offset is the first proving byte or first missing byte. Construct_Offset is eligible only
   --  when Has_Construct_Offset and carries the legacy checked-span anchor: head start for a
   --  truncated head, payload start for truncated payload, missing-child position for missing
   --  child, proving byte for malformed UTF-8, and retained lead only for incomplete UTF-8 at a
   --  CBOR chunk/payload end. Earlier primary diagnostics survive cleanup failure. Coordinate and
   --  Offset are eligible only when Code /= No_Error and Coordinate /= No_Coordinate. Secondary
   --  coordinate/offset are eligible only when Secondary /= No_Error. Every successful operation
   --  clears its output diagnostic; Clear sets both codes to No_Error, coordinates to No_Coordinate,
   --  offsets to zero, and Has_Construct_Offset to False.

   procedure Clear (Item : out Diagnostic);
end Flyology_CBOR.Errors;
