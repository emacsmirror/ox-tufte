;;; ox-tufte.el --- Tufte HTML org-mode export backend -*- lexical-binding: t; -*-

;; Copyright (C) 2023-2024 The Bayesians Inc.
;; Copyright (C) 2016-2022 Matthew Lee Hinman

;; Author: The Bayesians Inc.
;;         M. Lee Hinman
;; Maintainer: The Bayesians Inc.
;; Description: An org exporter for Tufte HTML
;; Keywords: org, tufte, html, outlines, hypermedia, calendar, wp
;; Version: 3.0.4
;; Package-Requires: ((org "9.5") (emacs "27.1"))
;; URL: https://github.com/ox-tufte/ox-tufte

;; This file is not part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This is an export backend for Org-mode that exports buffers to HTML that
;; is compatible with Tufte CSS - <https://edwardtufte.github.io/tufte-css/>.
;; The design goal is to "minimally" change the HTML structure as generated by
;; `ox-html' (with additional CSS as needed) to get behaviour that is equivalent
;; to Tufte CSS.

;;; Code:

(require 'ox)
(require 'ox-html)
(eval-when-compile (require 'cl-lib)) ;; for cl-assert

;;;; marginnote syntax support
(org-babel-lob-ingest
 (concat (file-name-directory (locate-library "ox-tufte")) "src/README.org"))

(add-to-list 'org-export-before-processing-functions
             #'ox-tufte--utils-macros-alist-enable)


;;; User-Configurable Variables

(defgroup org-export-tufte nil
  "Options for exporting Org mode files to Tufte-CSS themed HTML."
  :tag "Org Export Tufte HTML"
  :group 'org-export)

(defcustom org-tufte-feature-more-expressive-inline-marginnotes t
  "Non-nil enables marginnote-as-macro and marginnote-as-babelcall syntax."
  :group 'org-export-tufte
  :type 'boolean
  :safe #'booleanp)

(defcustom org-tufte-include-footnotes-at-bottom nil
  "Non-nil means to include footnotes at the bottom of the page.
This is in addition to being included as sidenotes.  Sidenotes are not shown on
very narrow screens (phones), so it may be useful to additionally include them
at the bottom."
  :group 'org-export-tufte
  :type 'boolean
  :safe #'booleanp)

(defcustom org-tufte-margin-note-symbol "&#8853;"
  "The symbol that is used as a viewability-toggle on small screens."
  :group 'org-export-tufte
  :type 'string
  :safe #'stringp)

(defcustom org-tufte-randid-limit 10000000
  "Upper limit when generating random IDs.

With default value of 10000000, there is ~0.2% chance of collision with 200
references."
  :group 'org-export-tufte
  :type 'integer
  :safe #'integerp)


;;; Define Back-End
(org-export-define-derived-backend 'tufte-html 'html
  :menu-entry
  '(?T "Export to Tufte-HTML"
       ((?H "As HTML buffer" org-tufte-export-as-html)
        (?h "As HTML file" org-tufte-export-to-html)
        (?o "As HTML file and open"
            (lambda (a s v b)
              (if a (org-tufte-export-to-html t s v b)
                (org-open-file (org-tufte-export-to-html nil s v b)))))))
  :options-alist
  '((:footnotes-section-p nil "footnotes-section-p"
                          org-tufte-include-footnotes-at-bottom))
  :translate-alist '((footnote-reference . org-tufte-footnote-reference)
                     ;; (src-block . org-tufte-src-block)
                     (link . org-tufte-maybe-margin-note-link)
                     (quote-block . org-tufte-quote-block)
                     (special-block . org-tufte-special-block)
                     (verse-block . org-tufte-verse-block)))


;;; Utility Functions

(defun ox-tufte--utils-filter-ptags (str)
  "Remove <p> tags from STR.

Sidenotes and margin notes must have <p> and </p> tags removed to conform with
the html structure that tufte.css expects."
  (replace-regexp-in-string "</?p.*?>" "" str))

(defun ox-tufte--utils-footnotes-section ()
  "Toggle Footnotes section HTML based on `org-tufte-include-footnotes-at-bottom'."
  (if org-tufte-include-footnotes-at-bottom
      org-html-footnotes-section
    "<!-- %s --><!-- %s -->"))

(defconst ox-tufte--utils-macros-alist
  `(("marginnote" .
     (lambda (&rest args)
       (let ((note (string-join args "\\\n")))
         (concat
          "@@html:"
          (ox-tufte--utils-margin-note note)
          "@@")))))
  "Additional macros that are available during export.")
(defun ox-tufte--utils-macros-alist-enable (backend)
  "Ensure that necessary macros are available when BACKEND is `ox-tufte'."
  (when (and (org-export-derived-backend-p backend 'tufte-html)
             org-tufte-feature-more-expressive-inline-marginnotes)
    (setq org-export-global-macros
          (append org-export-global-macros
                  ox-tufte--utils-macros-alist))))

(defun ox-tufte--utils-margin-note (desc)
  "Return HTML snippet after interpreting DESC as a margin note.

This intended to be called via the `marginnote' library-of-babel function."
  (if org-tufte-feature-more-expressive-inline-marginnotes
      (let* ((ox-tufte--mn-macro-templates org-macro-templates)
             ;; ^ copy buffer-local variable
             (exported-str
              (let* ((org-export-global-macros ;; make buffer macros accessible
                      (append ox-tufte--mn-macro-templates org-export-global-macros))
                     ;; footnotes nested within marginalia aren't supported
                     (org-html-footnotes-section "<!-- %s --><!-- %s -->"))
                (org-export-string-as desc 'html t)))
             (exported-newline-fix (replace-regexp-in-string
                                    "\n" " "
                                    (replace-regexp-in-string
                                     "\\\\\n" "<br>"
                                     exported-str)))
             (exported-para-fix (ox-tufte--utils-filter-ptags exported-newline-fix)))
        (ox-tufte--utils-margin-note-snippet exported-para-fix))
    ""))

(defun ox-tufte--utils-margin-note-snippet (text &optional idtag blob)
  "Generate html snippet for margin-note with TEXT.

TEXT shouldn't have any <p> tags (or behaviour is undefined).  If
<p> tags are needed, use BLOB which must be an HTML snippet of a
containing element with `marginnote' class.  BLOB is ignored
unless TEXT is nil.

IDTAG is used in the construction of the `id' that connects a
margin-notes visibility-toggle with the margin-note."
  (let ((mnid (format "mn-%s.%s" (or idtag "auto") (ox-tufte--utils-randid)))
        (content (if text
                     (format "<span class='marginnote'>%s</span>" text)
                   blob)))
    (format
     (concat
      "<label for='%s' class='margin-toggle'>"
      org-tufte-margin-note-symbol
      "</label>"
      "<input type='checkbox' id='%s' class='margin-toggle'>"
      "%s")
     mnid mnid
     content)))

(defun ox-tufte--utils-string-fragment-to-xml (str)
  "Parse string fragment via `libxml'.
STR is the xml fragment.

For the inverse, use something like `esxml-to-xml' (from package
`esxml').  This function is presently never used (an intermediate
version of `ox-tufte' used it)."
  (cl-assert (libxml-available-p))
  (with-temp-buffer
    (insert str)
    ;; we really want to use `libxml-parse-xml-region', but that's too
    ;; strict. `libxml-parse-html-region' is more lax (and that's good for us),
    ;; but it creates <html> and <body> tags when missing. since we'll only be
    ;; using this function on html fragments, we can assume these elements are
    ;; always added and thus are safe to strip away
    (caddr  ;; strip <body> tag
     (caddr ;; strip <html> tag
      (libxml-parse-html-region (point-min) (point-max))))))

(defun ox-tufte--utils-randid ()
  "Give a random number below the `org-tufte-randid-limit'."
  (random org-tufte-randid-limit))


;;; Common customizations to ensure compatibility with both tufte-css and
;;; ox-html

(defvar ox-tufte--sema-in-tufte-export nil
  "Currently in the midst of an export.")
(defvar ox-tufte--store-confirm-babel-evaluate nil
  "Store value of `org-confirm-babel-evaluate'.")

(defun ox-tufte--utils-permit-mn-babel-call (lang body)
  "Permit evaluation of marginnote babel-call.
LANG is the language of the code block whose text is BODY,"
  (if (and (string= lang "elisp")
           (string= body "(require 'ox-tufte)
(ox-tufte--utils-margin-note input)"))
      nil
    ox-tufte--store-confirm-babel-evaluate))
(defun ox-tufte--utils-entrypoint-funcall (filename function &rest args)
  "Call FUNCTION with ARGS in a \"normalized\" environment.
FILENAME is intended to be the file being processed by one of the
entrypoint function (e.g. `org-tufte-publish-to-html')."
  (let ((ox-tufte--store-confirm-babel-evaluate
         (if ox-tufte--sema-in-tufte-export
             ox-tufte--store-confirm-babel-evaluate
           org-confirm-babel-evaluate))
        (ox-tufte--sema-in-tufte-export t)
        (org-html-divs '((preamble "header" "preamble") ;; `header' i/o  `div'
                         (content "article" "content") ;; `article' for `tufte.css'
                         (postamble "footer" "postamble")) ;; `footer' i/o `div'
                       )
        (org-html-container-element "section") ;; consistent with `tufte.css'
        (org-html-checkbox-type 'html)
        (org-html-doctype "html5")
        (org-html-html5-fancy t)
        (org-confirm-babel-evaluate #'ox-tufte--utils-permit-mn-babel-call)
        (ox-tufte/tmp/lob-pre org-babel-library-of-babel))
    ;; FIXME: could this be obviated for mn-as-macro and mn-as-babelcall syntax?
    (when org-tufte-feature-more-expressive-inline-marginnotes
      (let ((inhibit-message t))         ;; silence lob ingestion messages
        (org-babel-lob-ingest filename))) ;; needed by `ox-tufte--utils-margin-note'
    (let ((output (apply function args)))
      (setq org-babel-library-of-babel ox-tufte/tmp/lob-pre)
      output)))

(defun ox-tufte--utils-get-export-output-extension (plist)
  "Get export filename extension based on PLIST."
  (concat
   (when (> (length org-html-extension) 0) ".")
   (or (plist-get plist :html-extension)
       org-html-extension
       "html")))


;;; Transcode Functions

(defun org-tufte-quote-block (quote-block contents info)
  "Transform a quote block into an epigraph in Tufte HTML style.
QUOTE-BLOCK CONTENTS INFO are as they are in `org-html-quote-block'."
  (let* ((ox-tufte/ox-html-qb-str (org-html-quote-block quote-block contents info))
         (ox-tufte/qb-caption (org-export-data
                               (org-export-get-caption quote-block) info))
         (ox-tufte/footer-content-maybe
          (if (org-string-nw-p ox-tufte/qb-caption)
              (format "<footer>%s</footer>" ox-tufte/qb-caption)
            nil)))
    (if ox-tufte/footer-content-maybe
        (replace-regexp-in-string
         "</blockquote>\\'"
         (concat ox-tufte/footer-content-maybe "</blockquote>")
         ox-tufte/ox-html-qb-str t t)
      ox-tufte/ox-html-qb-str)))

(defun org-tufte-verse-block (verse-block contents info)
  "Transcode a VERSE-BLOCK element from Org to HTML.
CONTENTS is verse block contents.  INFO is a plist holding
contextual information."
  (let* ((ox-tufte/ox-html-vb-str (org-html-verse-block verse-block contents info))
         (ox-tufte/vb-caption (org-export-data
                               (org-export-get-caption verse-block) info))
         (ox-tufte/footer-content
          (if (org-string-nw-p ox-tufte/vb-caption)
              (format "<footer>%s</footer>" ox-tufte/vb-caption)
            "")))
    (format "<div class='verse'><blockquote>\n%s\n%s</blockquote></div>"
          ox-tufte/ox-html-vb-str
          ox-tufte/footer-content)))

(defun org-tufte-footnote-section-advice (fun &rest args)
  "Modify `org-html-footnote-section' based on `:footnotes-section-p'.
FUN is `org-html-footnote-section' and ARGS is single-element
  list containing the plist (\"communication channel\")."
  (if ox-tufte--sema-in-tufte-export
      (let ((switch-p (plist-get (car args) :footnotes-section-p)))
        (if switch-p (apply fun args)
          ""))
    (apply fun args)))
(advice-add 'org-html-footnote-section
            :around #'org-tufte-footnote-section-advice)
;; ox-html: definition: id="fn.<id>"; href="#fnr.<id>"
(defun org-tufte-footnote-reference (footnote-reference _contents info)
  "Create a footnote according to the tufte css format.
FOOTNOTE-REFERENCE is the org element, CONTENTS is nil.  INFO is a
plist holding contextual information.

Modified from `org-html-footnote-reference' in `org-html'."
  (concat
   ;; Insert separator between two footnotes in a row.
   (let ((prev (org-export-get-previous-element footnote-reference info)))
     (when (eq (org-element-type prev) 'footnote-reference)
       (plist-get info :html-footnote-separator)))
   (let* ((ox-tufte/fn-num
           (org-export-get-footnote-number footnote-reference info))
          (ox-tufte/uid (ox-tufte--utils-randid))
          (ox-tufte/fn-inputid (format "fnr-in.%d.%s" ox-tufte/fn-num ox-tufte/uid))
          (ox-tufte/fn-labelid ;; first reference acts as back-reference
           (if (org-export-footnote-first-reference-p footnote-reference info)
               (format "fnr.%d" ox-tufte/fn-num) ;; this conforms to `ox-html.el'
             (format "fnr.%d.%s" ox-tufte/fn-num ox-tufte/uid)))
          (ox-tufte/fn-def
           (org-export-get-footnote-definition footnote-reference info))
          (ox-tufte/fn-data
           (org-trim (org-export-data ox-tufte/fn-def info)))
          (ox-tufte/fn-data-unpar
           ;; footnotes must have spurious <p> tags removed or they will not work
           (ox-tufte--utils-filter-ptags ox-tufte/fn-data)))
     (format
      (concat
       "<label id='%s' for='%s' class='margin-toggle sidenote-number'><sup class='numeral'>%s</sup></label>"
       "<input type='checkbox' id='%s' class='margin-toggle'>"
       "<span class='sidenote'><sup class='numeral'>%s</sup>%s</span>")
      ox-tufte/fn-labelid ox-tufte/fn-inputid ox-tufte/fn-num
      ox-tufte/fn-inputid
      ox-tufte/fn-num ox-tufte/fn-data-unpar))))

(defun org-tufte-special-block (special-block contents info)
  "Add support for block margin-note special blocks.
Pass SPECIAL-BLOCK CONTENTS and INFO to `org-html-special-block' otherwise."
  (let ((block-type (org-element-property :type special-block)))
    (cond
     ((string= block-type "marginnote")
      (ox-tufte--utils-margin-note-snippet
       nil nil (org-html-special-block special-block contents info)))
     ((and (string= block-type "figure")
           (org-html--has-caption-p special-block info)
           (not (member "iframe-wrapper" ;; FIXME: fix tufte-css before enabling
                        (split-string
                         (plist-get (org-export-read-attribute :attr_html special-block) :class)
                         " "))))
      ;; add support for captions on figures that `ox-html' lacks
      (let* ((caption (let ((raw (org-export-data
                                  (org-export-get-caption special-block) info)))
                        (if (not (org-string-nw-p raw)) raw
                          ;; FIXME: it would be nice to be able to count figure
                          ;; as an image and number accordingly
                          raw
                          ;; (concat "<span class=\"figure-number\">"
                          ;;         (format (org-html--translate "Figure %d:" info)
                          ;;                 (org-export-get-ordinal
                          ;;                  (org-element-map special-block 'link
                          ;;                    #'identity info t)
                          ;;                  info '(link) #'org-html-standalone-image-p))
                          ;;         " </span>"
                          ;;         raw)
                          )))
             (figcaption (format "<figcaption>%s</figcaption>" caption))
             ;; using regex because `esxml-to-xml' doesn't put closing iframe
             ;; tag (and also loses some attributes), which results in broken
             ;; html (so cannot do what we do in `org-tufte-quote-block'.
             (o-h-sb-str (org-html-special-block special-block contents info)))
        (replace-regexp-in-string
         "</figure>\\'"
         (concat figcaption "</figure>") o-h-sb-str t t)))
     (t (org-html-special-block special-block contents info)))))

(defun org-tufte-maybe-margin-note-link (link desc info)
  "Render LINK as a margin note if it begins with `mn:'.
For example, `[[mn:1][this is some text]]' is margin note 1 that
will show \"this is some text\" in the margin.

If it does not, it will be passed onto the original function in
order to be handled properly. DESC is the description part of the
link. INFO is a plist holding contextual information.

Defining margin-note link in this manner, as opposed to via
`org-link-set-parameters', ensures that margin-notes are only
handled when occurring as regular links and not as angle or plain
links. Additionally, it ensures that we only handle margin-notes
for HTML backend without having an opinion on how to treat them
for other backends."
  (let ((path (split-string (org-element-property :path link) ":"))
        (desc (or desc "")))
    (if (and (string= (org-element-property :type link) "fuzzy")
             (string= (car path) "mn"))
        (ox-tufte--utils-margin-note-snippet
         (ox-tufte--utils-filter-ptags desc)
         (if (string= (cadr path) "") nil (cadr path)))
      (org-html-link link desc info))))

(defun org-tufte-src-block (src-block _contents info)
  "Transcode SRC-BLOCK element into Tufte HTML format.
CONTENTS is nil.  INFO is a plist used as a communication channel.

NOTE: this is dead code and currently unused."
  (format "<pre class=\"code\"><code>%s</code></pre>"
          (org-html-format-code src-block info)))


;;; Export functions

;;;###autoload
(defun org-tufte-export-as-html
    (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer to a Tufte HTML buffer.

If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting buffer should be accessible
through the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree
at point, extracting information from the headline properties
first.

When optional argument VISIBLE-ONLY is non-nil, don't export
contents of hidden elements.

When optional argument BODY-ONLY is non-nil, only write code
between \"<body>\" and \"</body>\" tags.

EXT-PLIST, when provided, is a property list with external
parameters overriding Org default settings, but still inferior to
file-local settings.

Export is done in a buffer named \"*Org Tufte Export*\", which will
be displayed when `org-export-show-temporary-export-buffer' is
non-nil."
  (interactive)
  (ox-tufte--utils-entrypoint-funcall
   buffer-file-name
   #'org-export-to-buffer 'tufte-html "*Org Tufte Export*"
   async subtreep visible-only body-only ext-plist
   (lambda () (set-auto-mode t))))

;;;###autoload
(defun org-tufte-export-to-html
    (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer to a Tufte HTML file.

If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting file should be accessible through
the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree
at point, extracting information from the headline properties
first.

When optional argument VISIBLE-ONLY is non-nil, don't export
contents of hidden elements.

When optional argument BODY-ONLY is non-nil, only write code
between \"<body>\" and \"</body>\" tags.

EXT-PLIST, when provided, is a property list with external
parameters overriding Org default settings, but still inferior to
file-local settings.

Return output file's name."
  (interactive)
  (let ((file (org-export-output-file-name
               (ox-tufte--utils-get-export-output-extension ext-plist)
               subtreep)))
    (ox-tufte--utils-entrypoint-funcall
     buffer-file-name
     #'org-export-to-file 'tufte-html file
     async subtreep visible-only body-only ext-plist)))


;;; publishing function

;;;###autoload
(defun org-tufte-publish-to-html (plist filename pub-dir)
  "Publish an org file to Tufte-styled HTML.

PLIST is the property list for the given project.  FILENAME is
the filename of the Org file to be published.  PUB-DIR is the
publishing directory.

Return output file name."
  (ox-tufte--utils-entrypoint-funcall
   filename
   #'org-publish-org-to 'tufte-html filename
   (ox-tufte--utils-get-export-output-extension plist)
   plist pub-dir))

(provide 'ox-tufte)

;;; ox-tufte.el ends here
