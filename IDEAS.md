# TOPIC: Internal Representation

* Investigation - existing formatting languages and engines

Most existing formatting engines are build with the idea of text flowing from one page to the next.
This is incompatible with a slide deck.

nb. The KP Line Breaking Algorithm is considered world class and [not really supported by web](https://medium.com/@glitterliu617/on-typesetting-engines-a-programmers-perspective-58f537a353d7)

Some existing things have potential:

* LaTeX - The "beamer" documentclass can create slides

Beamer -> pandoc -> html is supported
absolute positioning in beamer is [difficult](https://tex.stackexchange.com/questions/682694/simple-way-to-position-a-text-anywhere-on-a-beamer-frame)

* fodp - "Flat" odp - an xml representation of the open document format

XML is verbose, but I think I read the llms are good at XML? investigate
ODP -> PDF is supported, but to get to html we need to go through beamer and pandoc

* pandoc supports [slidess]( https://pandoc.org/MANUAL.html#slide-shows)

[filters](https://daveho.github.io/2024/01/24/pandoc-for-presentations.html) - raw markdown conversion
pandoc supports LaTeX math syntax

We could also work directly on the pandoc AST

Pandoc makePDF internally uses LaTeX or HTML


----

# Fabric as WSYIWYG, internal representation, and Pandoc

Key requirements:                                                                                                 

 • Internal representation should support absolute positioning (as per TDD) and rich content.                     
 • Ability to render to WYSIWYG editor (web-based) and high-fidelity PDF.                                         
 • Avoid locking into a specific rendering library for the editor.                                                

Proposed approach:                                                                                                

 1 Define a Layout-Preserving Intermediate Representation (IR)                                                    
    • Extend Pandoc's AST with custom layout attributes OR use a separate layout tree that references content     
      nodes.                                                                                                      
    • Example IR structure:                                                                                       
                                                                                                                  
      {                                                                                                           
        "id": "element-123",                                                                                      
        "type": "text",                                                                                           
        "content": "Hello world",                                                                                 
        "metadata": { ... },                                                                                      
        "layout": {                                                                                               
          "page": 1,                                                                                              
          "x": 100,   // in points (1/72 inch)                                                                    
          "y": 200,                                                                                               
          "width": 300,                                                                                           
          "height": 50                                                                                            
        }                                                                                                         
      }                                                                                                           
                                                                                                                  
 2 Editor Implementation                                                                                          
    • Use a library (like Fabric.js, Konva, or Tldraw) only for the visual editing, but sync changes back to the  
      IR.                                                                                                         
    • Editor responsibilities:                                                                                    
       • Render the IR as boxes/text with absolute positioning.                                                   
       • Allow moving/resizing -> update IR's layout attributes.                                                  
       • Text editing -> update IR's content.                                                                     
 3 PDF Rendering                                                                                                  
    • Use a PDF library (like pdf-lib, puppeteer, or WeasyPrint) that supports absolute positioning.              
    • Map IR directly to PDF elements with precise coordinates.                                                   
 4 Pandoc Integration                                                                                             
    • If using Pandoc for content, we can: a) Keep content in Pandoc Markdown and store layout separately (linking
      by ID). b) Use Pandoc filters to inject layout during export (but layout might be lost in some formats).    

Evaluation of Libraries for Editor                                                                                

Given the requirement to have the editor as a view and not the source of truth, we can choose any library that    
allows:                                                                                                           

 • Binding external data (IR) to visual elements.                                                                 
 • Syncing user changes back to the IR.                                                                           

Fabric.js still works well here because:                                                                          

 • It has a robust object model that can be linked to IR via data attributes.                                     
 • Example:                                                                                                       
                                                                                                                  
   // Create Fabric object from IR                                                                                
   const irElement = { id: '123', content: 'Hello', layout: { x: 100, y: 100, width: 200, height: 50 } };         
   const text = new fabric.Textbox(irElement.content, {                                                           
     left: irElement.layout.x,                                                                                    
     top: irElement.layout.y,                                                                                     
     width: irElement.layout.width,                                                                               
     height: irElement.layout.height,                                                                             
     data: { id: irElement.id }  // Store reference to IR                                                         
   });                                                                                                            
                                                                                                                  
   // On change, update IR                                                                                        
   text.on('modified', () => {                                                                                    
     const updatedIR = findIRById(text.data.id);                                                                  
     updatedIR.layout.x = text.left;                                                                              
     updatedIR.layout.y = text.top;                                                                               
     updatedIR.layout.width = text.width;                                                                         
     updatedIR.layout.height = text.height;                                                                       
     updatedIR.content = text.text;                                                                               
   });                                                                                                            
                                                                                                                  

Tldraw is also a strong candidate because:                                                                        

 • It's designed for syncing with external state (via store).                                                     
 • Supports text boxes and shapes with absolute positioning.                                                      
 • More modern and might be easier for collaborative editing.                                                     

Pandoc AST with Layout Extension                                                                                  

If we want to stick with Pandoc, we can extend its AST with custom attributes for layout. However, note that:     

 • Pandoc's AST is designed for semantic content, not layout.                                                     
 • We can add attributes to block elements (like Div or Para) to store coordinates, but this is non-standard and  
   might break when converting to other formats.                                                                  

Alternative: Use a separate layout file (e.g., in YAML/JSON) that maps Pandoc element IDs to positions. Then,     
during rendering:                                                                                                 

 1 Render content to Pandoc AST (without layout).                                                                 
 2 Apply layout information in the target renderer (e.g., for PDF, place each element at its coordinates).        

Recommendation                                                                                                    

Do not use Pandoc as the primary internal representation for layout. Instead:                                     

 • Maintain a custom IR that separates content and layout (as described in the TDD).                              
 • Use Pandoc for content conversion (e.g., Markdown to formatted text) but not for layout.                       

Editor Library Choice:                                                                                            

 • Tldraw if you want a modern, collaborative-ready editor with easy state syncing.                               
 • Fabric.js if you need more control and maturity.                                                               

PDF Rendering:                                                                                                    

 • Use pdf-lib to place content at absolute positions based on the IR.                                            

Example Workflow                                                                                                  

 1 Internal Representation (stored in DB):                                                                        
                                                                                                                  
   {                                                                                                              
     "book": {                                                                                                    
       "pages": [                                                                                                 
         {                                                                                                        
           "id": "page1",                                                                                         
           "elements": [                                                                                          
             {                                                                                                    
               "id": "text1",                                                                                     
               "type": "text",                                                                                    
               "content": "## Heading\\nParagraph text",                                                          
               "layout": { "x": 100, "y": 100, "width": 200, "height": 50 }                                       
             }                                                                                                    
           ]                                                                                                      
         }                                                                                                        
       ]                                                                                                          
     }                                                                                                            
   }                                                                                                              
                                                                                                                  
 2 Editor (Tldraw/Fabric):                                                                                        
    • Render content as formatted text (using a Markdown renderer for Tldraw?).                                   
    • Position using layout.                                                                                      
 3 PDF Export:                                                                                                    
    • Convert Markdown content to styled text (using pdf-lib or via HTML+CSS).                                    
    • Draw at (x, y) with specified width/height.                                                                 

Need more details on any part?                                                                                    

------------------------------------------------------------------------------------------------------------------

► ANSWER                                                                                                          

Based on your requirements (editor as one view of internal primitives, multi-format output with layout fidelity), 
here's a revised approach:                                                                                        

Core Architecture Principles                                                                                      

 1 Single Source of Truth: Internal representation (IR) stores semantic content + layout constraints              
 2 Editor as a Renderer: WYSIWYG editor visualizes IR but doesn't store final state                               
 3 Output-Agnostic IR: Same IR drives PDF, web, print, etc. with format-specific renderers                        

Pandoc AST Limitations & Solutions                                                                                

                                                            
 Issue                    Solution                          
 ────────────────────────────────────────────────────────── 
 Weak layout control      Extend AST with layout primitives 
 No absolute positioning  Add coordinate metadata layer     
 Limited styling          Attach CSS-like rules to elements 
                                                            

Proposed IR Structure                                                                                             

                                                                                                                  
interface Element {                                                                                               
  id: UUID                                                                                                        
  type: 'text' | 'image' | 'shape'                                                                                
  content: string | Buffer | URL // Raw content                                                                   
  metadata: {                                                                                                     
    prompt?: string                                                                                               
    styles: { // Layout constraints                                                                               
      position?: 'absolute' | 'relative'                                                                          
      coordinates?: { x: number; y: number; unit: 'pt' | '%' }                                                    
      dimensions?: { w: number; h: number; unit: 'pt' | '%' }                                                     
    }                                                                                                             
  }                                                                                                               
  version: number                                                                                                 
}                                                                                                                 
                                                                                                                  

Editor Integration Strategy                                                                                       

                                                                                                                  
graph LR                                                                                                          
IR[Internal Representation] --> Editor                                                                            
IR --> PDF                                                                                                        
IR --> Web                                                                                                        
Editor -->|sync changes| IR                                                                                       
                                                                                                                  

Library Evaluation for Editor View                                                                                

 1 Tldraw (Best Fit)                                                                                              
    • ✅ Exposes document state as JSON                                                                           
    • ✅ Built-in support for absolute positioning                                                                
    • ✅ Mature React integration                                                                                 
    • ❗ Requires adapter to sync with IR                                                                         
 2 Fabric.js (Alternative)                                                                                        
    • ✅ Proven for coordinate-based editing                                                                      
    • ❗ Requires custom synchronization layer                                                                    
 3 Pandoc + Custom Overlay                                                                                        
    • ✅ Maintains semantic purity                                                                                
    • ❗ Complex to implement WYSIWYG                                                                             

PDF Fidelity Workflow                                                                                             

 1 During Editing:                                                                                                
    • Store all coordinates in print units (points)                                                               
    • Maintain hi-res assets separately                                                                           
 2 On Export:                                                                                                     
                                                                                                                  
   def export_pdf(elements):                                                                                      
     for e in elements:                                                                                           
       if e.type == 'text':                                                                                       
         pdf.draw_text(e.content, x=e.metadata.coordinates.x, y=e.metadata.coordinates.y)                         
       elif e.type == 'image':                                                                                    
         pdf.embed_image(e.content, x=e.metadata.coordinates.x, y=e.metadata.coordinates.y)                       

---

# Fabric vs Paged.js for WYSIWYG

Fabric.js Approach                                                                                                

                                                                                                                  
graph LR                                                                                                          
A[Canvas Editor] --> B[Normalized IR<br>0-1 coords]                                                               
B --> C[PDF Renderer]                                                                                             
B --> D[HTML Renderer]                                                                                            
                                                                                                                  

Pros:                                                                                                             

 • ✅ Direct manipulation: Native support for drag/resize of any element                                          
 • ✅ Visual fidelity: 1:1 editing experience with final layout intent                                            
 • ✅ Maturity: Production-ready with 24k+ GitHub stars                                                           
 • ✅ Coord flexibility: Normalized 0-1 coords work for any output size                                           
 • ✅ Text editing: Built-in in-canvas text editing                                                               

Cons:                                                                                                             

 • ❗ PDF conversion: Requires custom PDF renderer                                                                
 • ❗ Accessibility: Canvas elements harder for screen readers                                                    

------------------------------------------------------------------------------------------------------------------

Paged.js Approach                                                                                                 

                                                                                                                  
graph LR                                                                                                          
E[HTML/CSS Editor] --> F[CSS Layout IR]                                                                           
F --> G[PDF via Paged.js]                                                                                         
F --> H[HTML Renderer]                                                                                            
                                                                                                                  

Pros:                                                                                                             

 • ✅ Output fidelity: Same CSS → PDF with minimal conversion                                                     
 • ✅ Web standards: Uses native browser layout engine                                                            
 • ✅ Accessibility: Semantic HTML out-of-box                                                                     
 • ✅ Pagination: Built-in page break handling                                                                    

Cons:                                                                                                             

 • ❗ Positioning limits: Requires workarounds for absolute positioning:                                          
                                                                                                                  
   /* Manual coordinate conversion */                                                                             
   .element {                                                                                                     
     position: absolute;                                                                                          
     left: calc(25% * var(--page-width));                                                                         
     top: calc(50% * var(--page-height));                                                                         
   }                                                                                                              
                                                                                                                  
 • ❗ Editing experience: No built-in drag handles (requires external lib)                                        
 • ❗ Browser constraints: Chrome-only for advanced features                                                      

------------------------------------------------------------------------------------------------------------------

Key Comparison                                                                                                    

                                                                                
 Feature                Fabric.js                  Paged.js                     
 ────────────────────────────────────────────────────────────────────────────── 
 Arbitrary positioning  ✅ Native                  ⚠️ Possible with constraints 
 PDF fidelity           ⚠️ Custom renderer needed  ✅ 1:1 CSS→PDF               
 Text editing           ✅ Canvas-based            ⚠️ ContentEditable quirks    
 Multi-page support     ❌ Manual                  ✅ Built-in                  
 Learning curve         Medium                     Low (HTML/CSS)               
 Maturity               High (2010)                Medium (2018)                
 Accessibility          ⚠️ Limited                 ✅ Good  
