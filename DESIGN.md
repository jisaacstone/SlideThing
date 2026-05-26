Basic flow: [INPUTS] -> [INTERNAL REPRESENTATION] -> DECK

Internal representation:

DECK:
 DECK-METADATA
 SLIDES

SLIDES:
 SLIDE + SLIDES

SLIDE:
 SLIDE-METADATA
 COMPONENTS

COMPONENTS:
 COMPONENT + COMPONENTS

COMPONENT:
 COMPONENT-METADATA
 COMPONENT-VALUE

COMPONENT-VALUE
 TEXT
 IMAGE

---

The basic idea is that the internal representation can be generated or manually edited

There are three levels of work: DECK, SLIDE, COMPONENT.
At each level we have LOCKING and VERSIONING. LOCKING will preserve the value when re-generating the INTERNAL-REPRESENTATION from INPUTS.

INPUT -> REPRESENTATION flow can be run at any level. A full deck can be generated from an input. A single image can also be generated.

Examples:

I have a product spec (pdf) and some screenshots (png). I upload these to the interface, and write a prompt: "Generate a 3-4 slide presentation to present at the all hands to hype the new product launch".

The Inputs will become part of the deck metadata. The will also be passed to the internals to create the slides and components. The UI will show the generated slides.

I can then, for example, LOCK the first slide, and re-prompt: "The bullets should be shorter. Focus on user stories not technical implementation".

The first slide will remain the same, and the other slides will be re-generated. I can then decide actually I liked better the first image generated for the last slide. I can click on the generated image, and roll back to the previous version. I can also re-prompt for a single slide, or a single image.

So in this example we have some uploaded images. These will be default be included as-is. But I could add a prompt for a single image, eg "add a green roof to the building" and it would take the source image and the prompt, and generate a new image.

Technical Challenges:
Templating - most slides follow a simple template (Title only, Title and bullets, chart with short description, etc). Intelligently picking the correct template is important.
This can be rigid (model is given discreet choices) or dynamic (model is given some tooling and it can generate templates as-needed). We can also have some pre-defined user templates to create very rigid structure.

Which comes first: template or content? It makes most sense for the model first to generate a logical flow of content, and then the actual components, then the templates and slides, and finally run a formatting step.

Formatting: The model will need to intelligently decide if it should move things around, resize things, or edit the content. For text it could resize, change flow, reposition or change content. For Images it can resize, crop, reposition or regenerate. The agent will need to both identify problems and choose the correct solution. My experience is that agents are actually pretty bad at this. The UI should also allow for manual tweaking.

Theme/Palette - having metadata for an theme and/or palette will be desired - getting the model to actually follow has been a challenge for me in the past.

Questions:
Web editing of slides is probably a solved problem. Is there software existing we can build on top of?
What are the functional and other requirements?
Who are the target users? Initial launch, final market?
Size of screen - affects image resolution, text size?
