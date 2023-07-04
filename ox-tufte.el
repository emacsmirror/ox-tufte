;;; ox-tufte.el --- Tufte HTML org-mode export backend

;; Copyright (C) 2023      The Bayesians Inc.
;; Copyright (C) 2016-2023 Matthew Lee Hinman

;; Author: M. Lee Hinman
;; Maintainer: The Bayesians Inc.
;; Description: An org exporter for Tufte HTML
;; Keywords: org, tufte, html, outlines, hypermedia, calendar, wp
;; Version: 2.0.0
;; Package-Requires: ((org "9.5") (emacs "26.1") (esxml "0.3.7"))
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
;; is compatible with Tufte CSS - https://edwardtufte.github.io/tufte-css/ out of
;; the box (meaning no CSS modifications needed).

;;; Code:

(require 'ox)
(require 'ox-html)
(eval-when-compile (require 'cl-lib)) ;; for cl-assert
(require 'esxml)


;;; User-Configurable Variables

(defgroup org-export-tufte nil
  "Options specific to Tufte export back-end."
  :tag "Org Tufte"
  :group 'org-export
  :version "26.1"
  :package-version '(Org . "9.5"))

(defcustom org-tufte-include-footnotes-at-bottom nil
  "Non-nil means to include footnotes at the bottom of the page.
This is in addition to being included as sidenotes.  Sidenotes are not shown on
very narrow screens (phones), so it may be useful to additionally include them
at the bottom."
  :group 'org-export-tufte
  :type 'boolean)

(defcustom org-tufte-margin-note-symbol "&#8853;"
  "The symbol that is used as a viewability-toggle on small screens."
  :group 'org-export-tufte
  :type 'string)

(defcustom org-tufte-randid-limit 10000000
  "Upper limit when generating random IDs.

With default value of 10000000, there is ~0.2% chance of collision with 200
references."
  :group 'org-export-tufte
  :type 'integer)

;;;###autoload
(defun ox-tufte/init (&optional footnotes-at-bottom-p)
  "Initialize some `org-html' related settings.

FOOTNOTES-AT-BOTTOM-P initializes the value of
`org-tufte-include-footnotes-at-bottom'."
  (setq org-html-divs '((preamble "header" "preamble") ;; `header' i/o  `div'
                        (content "article" "content") ;; `article' for `tufte.css'
                        (postamble "footer" "postamble")) ;; `footer' i/o `div'
        org-html-container-element "section" ;; consistent with `tufte.css'
        org-html-checkbox-type 'html
        org-html-doctype "html5"
        org-html-html5-fancy t
        org-tufte-include-footnotes-at-bottom footnotes-at-bottom-p)
  (org-babel-lob-ingest
   (concat (file-name-directory (locate-library "ox-tufte")) "README.org")))


;;; Define Back-End

(org-export-define-derived-backend 'tufte-html 'html
  :menu-entry
  '(?T "Export to Tufte-HTML"
       ((?T "To temporary buffer"
            (lambda (a s v b) (org-tufte-export-to-buffer a s v)))
        (?t "To file" (lambda (a s v b) (org-tufte-export-to-file a s v)))
        (?o "To file and open"
            (lambda (a s v b)
              (if a (org-tufte-export-to-file t s v)
                (org-open-file (org-tufte-export-to-file nil s v)))))))
  :translate-alist '((footnote-reference . org-tufte-footnote-reference)
                     ;; (src-block . org-tufte-src-block)
                     (link . org-tufte-maybe-margin-note-link)
                     (quote-block . org-tufte-quote-block)
                     (verse-block . org-tufte-verse-block)))


;;; Utility Functions

(defun ox-tufte/utils/filter-ptags (str)
  "Remove <p> tags from STR.

Sidenotes and margin notes must have <p> and </p> tags removed to conform with
the html structure that tufte.css expects."
  (replace-regexp-in-string "</?p.*?>" "" str))

;;;###autoload
(defun ox-tufte/utils/margin-note (desc)
  "Return HTML snippet after interpreting DESC as a margin note.

This intended to be called via the `marginnote' library-of-babel function."
  (let* ((exported-str
          (progn
            ;; (save-excursion
            ;;   (message "HMM: desc = '%s'" desc)
            ;;   (message "HMM: buffer-string = '%s'" (buffer-string))
            ;;   (goto-char (point-min))
            ;;   (let ((end (search-forward desc))
            ;;         (beg (match-beginning 0)))
            ;;     (narrow-to-region beg end)
            ;;     (let ((output-buf (org-html-export-as-html nil nil
            ;;                                                nil t)))
            ;;       (widen)
            ;;       (with-current-buffer output-buf
            ;;         (buffer-string)))))
            (with-temp-buffer
              ;; FIXME: use narrowing instead to obviate having to add functions
              ;; to library-of-babel in `org-html-publish-to-tufte-html' etc.
              (insert desc)
              (let ((output-buf
                     (org-html-export-as-html nil nil nil t)))
                (with-current-buffer output-buf
                  (buffer-string))))
            ))
         (exported-newline-fix (replace-regexp-in-string
                                "\n" " "
                                (replace-regexp-in-string
                                 "\\\\\n" "<br>"
                                 exported-str)))
         (exported-para-fix (ox-tufte/utils/filter-ptags exported-newline-fix)))
    (ox-tufte/utils/margin-note/snippet exported-para-fix)))

(defun ox-tufte/utils/margin-note/snippet (content &optional idtag)
  "Generate html snippet for margin-note with CONTENT.

CONTENT shouldn't have any '<p>' tags (or behaviour is undefined).  IDTAG is
  used in the construction of the 'id' that connects a margin-notes
  visibility-toggle with the margin-note."
  (let ((mnid (format "mn-%s.%s" (or idtag "auto") (ox-tufte/utils/randid))))
    (format
     (concat
      "<label for='%s' class='margin-toggle'>"
      org-tufte-margin-note-symbol
      "</label>"
      "<input type='checkbox' id='%s' class='margin-toggle'>"
      "<span class='marginnote'>%s</span>")
     mnid mnid
     content)))

(defun ox-tufte/utils/string-fragment-to-xml (str)
  "Parse string fragment via `libxml'.
STR is the xml fragment.

For the inverse, use `esxml-to-xml'."
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

(defun ox-tufte/utils/randid ()
  "Give a random number below the `org-tufte-randid-limit'."
  (random org-tufte-randid-limit))


;;; Transcode Functions

(defun org-tufte-quote-block (quote-block contents info)
  "Transform a quote block into an epigraph in Tufte HTML style.
QUOTE-BLOCK CONTENTS INFO are as they are in `org-html-quote-block'."
  (let* ((ox-tufte/ox-html-qb-str (org-html-quote-block quote-block contents info))
         (ox-tufte/ox-html-qb-dom
          (ox-tufte/utils/string-fragment-to-xml ox-tufte/ox-html-qb-str))
         (ox-tufte/qb-name (org-element-property :name quote-block))
         (ox-tufte/footer-content-maybe
          (if ox-tufte/qb-name
              (format "<footer>%s</footer>" ox-tufte/qb-name)
            nil)))
    (when ox-tufte/footer-content-maybe
      (push (ox-tufte/utils/string-fragment-to-xml ox-tufte/footer-content-maybe)
            (cdr (last ox-tufte/ox-html-qb-dom))))
    (format "<div class='epigraph'>%s</div>"
            (if ox-tufte/footer-content-maybe ;; then we would've modified qb-dom
                (esxml-to-xml ox-tufte/ox-html-qb-dom)
              ox-tufte/ox-html-qb-str))
    ))

(defun org-tufte-verse-block (verse-block contents info)
  "Transcode a VERSE-BLOCK element from Org to HTML.
CONTENTS is verse block contents.  INFO is a plist holding
contextual information."
  (let* ((ox-tufte/ox-html-vb-str (org-html-verse-block verse-block contents info))
         (ox-tufte/vb-name (org-element-property :name verse-block))
         (ox-tufte/footer-content
          (if ox-tufte/vb-name
              (format "<footer>%s</footer>" ox-tufte/vb-name)
            "")))
    (format "<div class='verse'><blockquote>\n%s\n%s</blockquote></div>"
          ox-tufte/ox-html-vb-str
          ox-tufte/footer-content)
    ))

;; ox-html: definition: id="fn.<id>"; href="#fnr.<id>"
(defun org-tufte-footnote-reference (footnote-reference contents info)
  "Create a footnote according to the tufte css format.
FOOTNOTE-REFERENCE is the org element, CONTENTS is nil.  INFO is a
plist holding contextual information.

Modified from `org-html-footnote-reference' in 'org-html'."
  (concat
   ;; Insert separator between two footnotes in a row.
   (let ((prev (org-export-get-previous-element footnote-reference info)))
     (when (eq (org-element-type prev) 'footnote-reference)
       (plist-get info :html-footnote-separator)))
   (let* ((ox-tufte/fn-num
           (org-export-get-footnote-number footnote-reference info))
          (ox-tufte/uid (ox-tufte/utils/randid))
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
           (ox-tufte/utils/filter-ptags ox-tufte/fn-data))
          )
     (format
      (concat
       "<label id='%s' for='%s' class='margin-toggle sidenote-number'><sup class='numeral'>%s</sup></label>"
       "<input type='checkbox' id='%s' class='margin-toggle'>"
       "<span class='sidenote'><sup class='numeral'>%s</sup>%s</span>")
      ox-tufte/fn-labelid ox-tufte/fn-inputid ox-tufte/fn-num
      ox-tufte/fn-inputid
      ox-tufte/fn-num ox-tufte/fn-data-unpar)
     )))

(defun org-tufte-maybe-margin-note-link (link desc info)
  "Render LINK as a margin note if it begins with `mn:'.
For example, `[[mn:1][this is some text]]' is margin note 1 that
will show \"this is some text\" in the margin.

If it does not, it will be passed onto the original function in
order to be handled properly. DESC is the description part of the
link. INFO is a plist holding contextual information.

NOTE: this style of margin-notes are DEPRECATED and may be deleted in a future
  version."
  (let ((path (split-string (org-element-property :path link) ":")))
    (if (and (string= (org-element-property :type link) "fuzzy")
             (string= (car path) "mn"))
        (ox-tufte/utils/margin-note/snippet
         (ox-tufte/utils/filter-ptags desc) (if (string= (cadr path) "") nil
                                              (cadr path)))
      (org-html-link link desc info))))

(defun org-tufte-src-block (src-block contents info)
  "Transcode SRC-BLOCK element into Tufte HTML format.
CONTENTS is nil.  INFO is a plist used as a communication channel.

NOTE: this is dead code and currently unused."
  (format "<pre class=\"code\"><code>%s</code></pre>"
          (org-html-format-code src-block info)))


;;; Export functions

;;;###autoload
(defun org-tufte-export-to-buffer (&optional async subtreep visible-only)
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

Export is done in a buffer named \"*Org Tufte Export*\", which will
be displayed when `org-export-show-temporary-export-buffer' is
non-nil."
  (interactive)
  (let (;; need to bind this because tufte treats footnotes specially, so we
        ;; don't want to display them at the bottom
        (org-html-footnotes-section (if org-tufte-include-footnotes-at-bottom
                                        org-html-footnotes-section
                                      "<!-- %s --><!-- %s -->"))
        (ox-tufte/tmp/lob-pre org-babel-library-of-babel))
    (org-babel-lob-ingest buffer-file-name) ;; needed by `ox-tufte/utils/margin-note'
    (let ((output (org-export-to-buffer 'tufte-html "*Org Tufte Export*"
                    async subtreep visible-only nil nil (lambda ()
                                                          (text-mode)))))
      (setq org-babel-library-of-babel ox-tufte/tmp/lob-pre)
      output)))

;;;###autoload
(defun org-tufte-export-to-file (&optional async subtreep visible-only)
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

Return output file's name."
  (interactive)
  (let ((outfile (org-export-output-file-name ".html" subtreep))
        ;; need to bind this because tufte treats footnotes specially, so we
        ;; don't want to display them at the bottom
        (org-html-footnotes-section (if org-tufte-include-footnotes-at-bottom
                                        org-html-footnotes-section
                                      "<!-- %s --><!-- %s -->"))
        (ox-tufte/tmp/lob-pre org-babel-library-of-babel))
    (org-babel-lob-ingest buffer-file-name) ;; needed by `ox-tufte/utils/margin-note'
    (let ((output (org-export-to-file 'tufte-html outfile async subtreep
                                      visible-only)))
      (setq org-babel-library-of-babel ox-tufte/tmp/lob-pre)
      output)))


;;; publishing function

;;;###autoload
(defun org-html-publish-to-tufte-html (plist filename pub-dir)
  "Publish an org file to Tufte-styled HTML.

PLIST is the property list for the given project.  FILENAME is
the filename of the Org file to be published.  PUB-DIR is the
publishing directory.

Return output file name."

  (let ((org-html-footnotes-section (if org-tufte-include-footnotes-at-bottom
                                        org-html-footnotes-section
                                      "<!-- %s --><!-- %s -->"))
        (ox-tufte/tmp/lob-pre org-babel-library-of-babel))
    (org-babel-lob-ingest filename) ;; needed by `ox-tufte/utils/margin-note'
    (let ((output (org-publish-org-to 'tufte-html filename
                                      (concat "." (or (plist-get plist :html-extension)
                                                      org-html-extension
                                                      "html"))
                                      plist pub-dir)))
      (setq org-babel-library-of-babel ox-tufte/tmp/lob-pre)
      output)))

(provide 'ox-tufte)

;;; ox-tufte.el ends here
