with Ada.Streams;
with Flyology_CBOR.Errors;
with Flyology_CBOR.Profiles;
with Flyology_CBOR.Values;
with Interfaces;
private with Ada.Containers.Vectors;
private with Flyology_CBOR.Destinations;
private with Flyology_CBOR.Writer_Engine;

package Flyology_CBOR.Allocating_Writing is
   --  Writer is single-owner and not task-safe. It owns explicitly allocating unpublished staging.
   --  Mutation-time Storage_Error enters Failed, makes partial staging ineligible, then re-raises.
   --  Scope exit discards unpublished staging and cannot publish it. No retained self-reference or
   --  controlled finalizer is required.
   type Writer_State is
     (Uninitialized,
      Ready,
      Active,
      Completed,
      Failed,
      Aborted);

   type Writer (Maximum_Syntax_Depth : Natural) is limited private;

   --  Lifecycle, diagnostics, fragment, count, UTF-8, and simple-value rules match the generic
   --  Writing facade. Text lengths are encoded octet counts and map lengths are pair counts.

   procedure Initialize
     (Self       : in out Writer;
      Profile    : Profiles.Writer_Profile;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Document
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Unsigned
     (Self       : in out Writer;
      Value      : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Negative_Argument
     (Self       : in out Writer;
      Argument   : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Signed
     (Self       : in out Writer;
      Value      : Interfaces.Integer_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_False
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_True
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Null
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Undefined
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Simple
     (Self       : in out Writer;
      Value      : Values.Simple_Code;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Float
     (Self       : in out Writer;
      Value      : Values.Float_Value;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Byte_String
     (Self       : in out Writer;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Indefinite_Byte_String
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Byte_String_Chunk
     (Self       : in out Writer;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Byte_String_Fragment
     (Self       : in out Writer;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Byte_String_Chunk
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Byte_String
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Text_String
     (Self         : in out Writer;
      Octet_Length : Interfaces.Unsigned_64;
      Diagnostic   : out Errors.Diagnostic);

   procedure Begin_Indefinite_Text_String
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Text_String_Chunk
     (Self         : in out Writer;
      Octet_Length : Interfaces.Unsigned_64;
      Diagnostic   : out Errors.Diagnostic);

   procedure Put_Text_String_Fragment
     (Self       : in out Writer;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Text_String_Chunk
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Text_String
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Array
     (Self       : in out Writer;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Indefinite_Array
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Array
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Map
     (Self       : in out Writer;
      Pair_Count : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Indefinite_Map
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Map
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Tag
     (Self       : in out Writer;
      Number     : Values.Tag_Number;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Tag
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Finish_Document
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Abort_Document
     (Self       : in out Writer;
      Diagnostic : out Errors.Diagnostic);

   procedure Reset
     (Self       : in out Writer;
      Profile    : Profiles.Writer_Profile;
      Diagnostic : out Errors.Diagnostic);

   function State (Self : Writer) return Writer_State;
   function Has_Applied_Profile (Self : Writer) return Boolean;

   function Applied_Profile (Self : Writer) return Profiles.Writer_Profile
   with Pre => Has_Applied_Profile (Self);

   function Terminal_Diagnostic (Self : Writer) return Errors.Diagnostic
   with Pre => State (Self) in Failed | Aborted;

   function Committed_Length
     (Self : Writer) return Ada.Streams.Stream_Element_Count
   with Pre => State (Self) = Completed;

   function Output
     (Self : Writer) return Ada.Streams.Stream_Element_Array
   with Pre => State (Self) = Completed;
   --  Output returns a separate array whose lower bound is one. A copy-time Storage_Error leaves
   --  the completed writer unchanged and retryable.

private
   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Ada.Streams.Stream_Element,
      "="          => Ada.Streams."=");

   type Destination is limited record
      Data             : Byte_Vectors.Vector;
      Committed        : Ada.Streams.Stream_Element_Count := 0;
      Transaction_Open : Boolean := False;
      Storage_Failed   : Boolean := False;
   end record;

   procedure Destination_Begin
     (Target : in out Destination;
      Status : out Destinations.Begin_Status);

   procedure Destination_Write
     (Target  : in out Destination;
      Data    : Ada.Streams.Stream_Element_Array;
      Written : out Ada.Streams.Stream_Element_Count;
      Status  : out Destinations.Write_Status);

   procedure Destination_Commit
     (Target : in out Destination;
      Status : out Destinations.Commit_Status);

   procedure Destination_Abort
     (Target : in out Destination;
      Status : out Destinations.Abort_Status);

   package Engine is new Flyology_CBOR.Writer_Engine
     (Destination_Type   => Destination,
      Destination_Begin  => Destination_Begin,
      Destination_Write  => Destination_Write,
      Destination_Commit => Destination_Commit,
      Destination_Abort  => Destination_Abort);

   type Writer (Maximum_Syntax_Depth : Natural) is limited record
      Target : Destination;
      Core   : Engine.Writer (Maximum_Syntax_Depth);
   end record;
end Flyology_CBOR.Allocating_Writing;
