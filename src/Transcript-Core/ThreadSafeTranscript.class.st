"
I'm an output device.
    Transcript show: 'hello'.

I implement TTranscript.

While ThreadSafeTranscript is threadsafe wrt stream access, the morphic code invoked by #changed: is not. So #changed: should not be sent from multiple threads (at random times) since this causes a morph's #update: method to conflict with the UI-thread running the morph's #drawOn: method in parallel. Whereas Morphic seems to assume that #update: and #drawOn: are run sequentially from the same thread.

The #step method is assumed to be invoked only from the main UI thread, so from here it is safe to send #changed: and consequently #update:. Methods #clear and #endEntry are invoked from multiple threads, so these signal to #step to call #changed: with the required parameter (#clearText and #appendEntry respectively.)

Method #contents should not directly return ==stream contents==, since even with a mutex around that, multiple calls from Morphic may unexpectedly get different results and fail.  #contents needs to return a value that is static between each #step (which is ==stepContents== that is only udpated in #step).

The ==stream reset== is left to occur from #clear being invoked from multiple threads. 

The ==stream resetContents== is moved to #step so this occurs directly after ==stepContents== is set from ==stream contents==.




"
Class {
	#name : #ThreadSafeTranscript,
	#superclass : #Model,
	#instVars : [
		'stream',
		'accessSemaphore',
		'deferredClear',
		'deferredEndEntry',
		'stepContents'
	],
	#category : #'Transcript-Core-Base'
}

{ #category : #declare }
ThreadSafeTranscript class >> install [

	self installThreadSafeAsTranscript
]

{ #category : #declare }
ThreadSafeTranscript class >> installThreadSafeAsSTranscript [

	Smalltalk globals at: #STranscript put: (self new)
	
	"ThreadSafeTranscript open"
]

{ #category : #declare }
ThreadSafeTranscript class >> installThreadSafeAsTranscript [

	Smalltalk globals at: #Transcript put: (self new)

	"ThreadSafeTranscript open"
]

{ #category : #icons }
ThreadSafeTranscript class >> taskbarIconName [
	"Answer the icon for the receiver in a task bar."

	^#transcriptIcon
]

{ #category : #streaming }
ThreadSafeTranscript >> << anObject [
	"Output anObject asString on the receiver and show the output"
	
	self show: anObject
]

{ #category : #accessing }
ThreadSafeTranscript >> characterLimit [

	^ 20000
]

{ #category : #streaming }
ThreadSafeTranscript >> clear [ 
"	Clear all characters by resetting the stream and voiding any previously flagged deferredEndEntry.
	Redisplays the view by signalling for #step to send #changed: .
"	
	self 
		critical: [ 
			deferredClear := true.
			deferredEndEntry := false.
			stream reset ]
]

{ #category : #streaming }
ThreadSafeTranscript >> close [
	self flush.
	self critical: [ stream close ]
	
]

{ #category : #'protected low level' }
ThreadSafeTranscript >> contents [ 
"	Cannot directly return == stream contents == since Morphic assumes multiple calls will return 
	the same value within the one cycle.  WorldState>>runStepMethodsIn:  sends #step to 
	do == stepContents := stream contents ==.
"
	^ stepContents
]

{ #category : #streaming }
ThreadSafeTranscript >> cr [
	"Output a cr on the receiver, buffered and not yet shown"
	
	self nextPut: Character cr
]

{ #category : #streaming }
ThreadSafeTranscript >> crShow: anObject [
	"Output anObject asString on the receiver preceded by a cr and show the output"
	
	self critical: [ self cr; show: anObject ]
]

{ #category : #streaming }
ThreadSafeTranscript >> critical: block [
	"Execute block making sure only one thread accesses the receiver"

	^ accessSemaphore critical: block 
]

{ #category : #streaming }
ThreadSafeTranscript >> endEntry [
"	Signal to #step to display all the characters since the last #step. 
	Stream is reset there.
"  
  	self critical: [ deferredEndEntry := true ].
]

{ #category : #streaming }
ThreadSafeTranscript >> flush [
	self endEntry

]

{ #category : #'ui building' }
ThreadSafeTranscript >> initialExtent [
	
	^447@300
]

{ #category : #initialization }
ThreadSafeTranscript >> initialize [
 
	super initialize.
	accessSemaphore := Mutex new.
	stream := String new writeStream.
	deferredClear := false.
	deferredEndEntry := false.
	stepContents := ''.

	
]

{ #category : #'self evaluating' }
ThreadSafeTranscript >> isSelfEvaluating [

	^self == Transcript 
		ifTrue: [ true ]
		ifFalse: [ super isSelfEvaluating ]
]

{ #category : #accessing }
ThreadSafeTranscript >> menu [
	" return nil to let the editing mode build the right menu"
	^nil
]

{ #category : #streaming }
ThreadSafeTranscript >> nextPut: value [
	"Output character on the receiver, buffered, not yet shown"

	self critical: [ stream nextPut: value ].
	^ value
]

{ #category : #streaming }
ThreadSafeTranscript >> nextPutAll: value [
	"Output string on the receiver, buffered, not yet shown"

	self critical: [ stream nextPutAll: value ].
	^ value
]

{ #category : #streaming }
ThreadSafeTranscript >> print: anObject [
	"Output anObject asString on the receiver, buffered, not yet shown"
	
	self nextPutAll: anObject asString
]

{ #category : #printing }
ThreadSafeTranscript >> printOn: aStream [

	self == Transcript ifFalse: [^super printOn: aStream].
	aStream nextPutAll: 'Transcript'
]

{ #category : #streaming }
ThreadSafeTranscript >> show: anObject [
	"Output anObject asString on the receiver and show the output"
	
	self critical: [ self print: anObject; endEntry ]
]

{ #category : #streaming }
ThreadSafeTranscript >> space [
	"Output a space on the receiver, buffered and not yet shown"

	self nextPut: Character space
]

{ #category : #updating }
ThreadSafeTranscript >> stepGlobal [
"	The superclass method Model>>step indicates a convention that might be used to interoperate 
	synchronously with the UI-thread.  However when multiple Transcript windows are open, their 
	PluggableTextMorphs share a single instance, from the global Transcript.  To avoid potential trouble, 
	this method should not be named #step.  
	
	As well, we need this method to execute even when no Transcript windows are open, so the stream 
	continues to be reset periodically, otherwise it would grow indefinitely. So this method is invoked 
	from WorldState>>runStepMethodsIn:. 
"

	"Next three lines required temporarily to initialize instance variables added to existing instance"
	deferredClear ifNil: [ deferredClear := false ].
	deferredEndEntry ifNil: [ deferredEndEntry := false ].
	stepContents ifNil: [ stepContents := '' ].
	
	deferredClear ifTrue: 
	[ 	deferredClear := false.  
		stepContents := ''.
		self changed: #clearText.
	].
	deferredEndEntry ifTrue: 
	[	deferredEndEntry := false.  	
		self critical: 
		[	stepContents := stream contents.
			stream resetContents.	
		].
		self changed: #appendEntry.	
	].
	
]

{ #category : #streaming }
ThreadSafeTranscript >> tab [
	"Output a tab on the receiver, buffered and not yet shown"

	self nextPut: Character tab
]

{ #category : #'ui building' }
ThreadSafeTranscript >> title [

	^ 'Transcript'
]
