with Ada.Streams;
with Flyology_CBOR.Destinations;
with Flyology_CBOR.Errors;
with Flyology_CBOR.Profiles;
with Flyology_CBOR.Values;
with Interfaces;
private with Flyology_CBOR.Writer_Engine;

generic
   --  Destination_Type and every writer instance are single-owner and not task-safe. The caller
   --  passes the same exclusive Target object throughout one active transaction.
   type Destination_Type is limited private;

   --  Every destination formal is synchronous, finite, nonraising, nonreentrant, and retains no
   --  reference to Target or supplied data. Violating one of these generic contracts propagates
   --  any exception and requires both writer and target to be discarded; no lifecycle state is
   --  promised. Concurrent use, task abort, or ATC during a writer call has the same disposition.
   with procedure Destination_Begin
     (Target : in out Destination_Type;
      Status : out Destinations.Begin_Status);

   with procedure Destination_Write
     (Target  : in out Destination_Type;
      Data    : Ada.Streams.Stream_Element_Array;
      Written : out Ada.Streams.Stream_Element_Count;
      Status  : out Destinations.Write_Status);

   --  Write_Succeeded reports Written = Data'Length. Write_Exhausted reports the exact
   --  longest accepted prefix, with 0 <= Written < Data'Length and Data nonempty. Write_Failed
   --  reports Written = 0. Empty data can report only Write_Succeeded with Written = 0.

   with procedure Destination_Commit
     (Target : in out Destination_Type;
      Status : out Destinations.Commit_Status);

   with procedure Destination_Abort
     (Target : in out Destination_Type;
      Status : out Destinations.Abort_Status);

package Flyology_CBOR.Writing is
   --  Initialize: Uninitialized -> Ready or Failed. Begin_Document: Ready -> Active or Failed.
   --  Contract-conforming mutation failure aborts after the destination call returns and enters
   --  Failed. Finish_Document enters Completed only after Commit_Succeeded; Commit_Failed aborts
   --  and enters Failed. Explicit abort maps Ready or Active to Aborted; Abort_Failed is primary
   --  only when no earlier primary exists. Completed output is never revoked. Reset is admitted
   --  only in Completed, Failed, or Aborted. Failed and Aborted retain their terminal diagnostic.
   type Writer_State is
     (Uninitialized,
      Ready,
      Active,
      Completed,
      Failed,
      Aborted);

   type Writer (Maximum_Syntax_Depth : Natural) is limited private;

   --  Every fragment array may have arbitrary bounds, is consumed synchronously, and is not
   --  retained. String Length and Octet_Length parameters count encoded payload octets. Map
   --  Pair_Count counts pairs. Definite calls enforce exact counts. Indefinite strings admit only
   --  explicit definite chunks. Text validates UTF-8 through every fragment and completes each
   --  CBOR chunk at a scalar boundary. Put_Simple accepts 0 .. 19 or 32 .. 255; 20 .. 23 use the
   --  specialized calls and 24 .. 31 are rejected with Invalid_Simple_Value.
   --
   --  Every successful call clears Diagnostic. Invalid UTF-8 and declared string-length failures
   --  use Writer_Token_Byte over aggregate token octets. Destination_Exhausted identifies the first
   --  unaccepted Staged_Output_Byte; Destination_Failed identifies the staged offset before the
   --  failed write. Grammar, depth, and invalid-simple failures use the zero-based CBOR_Call_Ordinal
   --  of the admitted semantic emission call; successful semantic calls increment it once. Begin
   --  failure uses staged offset zero. Commit_Failed uses the staged length. Abort_Failed uses that
   --  same coordinate as primary only without an earlier error, otherwise as secondary. Cleanup
   --  never replaces the earlier primary.

   procedure Initialize
     (Self       : in out Writer;
      Profile    : Profiles.Writer_Profile;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Document
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Unsigned
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Negative_Argument
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Argument   : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Signed
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Interfaces.Integer_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_False
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_True
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Null
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Undefined
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Simple
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Values.Simple_Code;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Float
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Values.Float_Value;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Byte_String
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Indefinite_Byte_String
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Byte_String_Chunk
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Byte_String_Fragment
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Byte_String_Chunk
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Byte_String
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Text_String
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Octet_Length : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Indefinite_Text_String
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Text_String_Chunk
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Octet_Length : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Put_Text_String_Fragment
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Value      : Ada.Streams.Stream_Element_Array;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Text_String_Chunk
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Text_String
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Array
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Length     : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Indefinite_Array
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Array
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Map
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Pair_Count : Interfaces.Unsigned_64;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Indefinite_Map
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Map
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure Begin_Tag
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Number     : Values.Tag_Number;
      Diagnostic : out Errors.Diagnostic);

   procedure End_Tag
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure Finish_Document
     (Self       : in out Writer;
      Target     : in out Destination_Type;
      Diagnostic : out Errors.Diagnostic);

   procedure Abort_Document
     (Self       : in out Writer;
      Target     : in out Destination_Type;
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

private
   package Engine is new Flyology_CBOR.Writer_Engine
     (Destination_Type   => Destination_Type,
      Destination_Begin  => Destination_Begin,
      Destination_Write  => Destination_Write,
      Destination_Commit => Destination_Commit,
      Destination_Abort  => Destination_Abort);

   type Writer (Maximum_Syntax_Depth : Natural) is limited record
      Core : Engine.Writer (Maximum_Syntax_Depth);
   end record;
end Flyology_CBOR.Writing;
