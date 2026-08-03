# Code Organization

The way you organize your code is important. As I'm sure you can imagine. The following lays out a structure that has worked well for me the last 10+ years and has evolved through many different approaches.

> Software is complete only when the results are shared with our customers
>
> _Paraphrase of the APA style guide_

* Writing Software
  * types of software projects
  * ethics and legal standards
  * ensuring accuracy
* Manuscript structure and content
  * standards
  * manuscript elements
  * sample projects
* writing clearly and concisely
  * Organization
  * writing style
  * reducing complexity scores?
  * 
* the mechanics of style
  * punctuation
  * spelling
  * etc
* displaying results
  * UI?

A rough translation of the outline presented in the _Publication Manual of the American Psychological Association_.


## Junk Drawers

How often have you accumulated a "junk drawer" in your code base? I'm talking about the folder called "models", "services", or some equally non-meaning folder that you just pour code into. Class after class is added and over time you can have one folder with hundreds of items in it.

It can be nice that everything is in one flat namespace. But you give me no direction when I'm starting on your project to know what are the key classes? What is at the root of the solution. The Junk Drawer is one my personal anti-patterns.

