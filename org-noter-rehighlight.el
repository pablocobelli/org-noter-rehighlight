;;; org-noter-rehighlight.el --- Reapply org-noter highlights as pdf-tools annotations -*- lexical-binding: t; -*-

;; Author: Pablo Cobelli
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.4") (pdf-tools "1.0"))
;; Keywords: outlines, pdf, org, annotations
;; URL: https://example.invalid/org-noter-rehighlight
;;
;; This file is not part of GNU Emacs.

;;; Commentary:
;;
;; org-noter-rehighlight provides commands to "rehydrate" highlights recorded by
;; org-noter (vedang/org-noter + pdf-tools backend) into pdf-tools *session*
;; annotations, without modifying the PDF file (unless you explicitly save it).
;;
;; The :HIGHLIGHT: property stored in org-noter notes contains a serialized
;; `pdf-highlight` struct. This package extracts the region payload (the same
;; shape as `pdf-view-active-region`) and feeds it to
;; `pdf-annot-add-highlight-markup-annotation`.
;;
;; Main entry points:
;; - `org-noter-rehighlight-at-point`
;; - `org-noter-rehighlight-buffer-batch`
;;
;; Notes:
;; - These commands must be run from an org-noter notes buffer with an active
;;   `org-noter--session` and a PDF opened with pdf-tools.
;; - Annotations are created in-session; do NOT save the PDF if you want it
;;   immutable.

;;; Code:

(require 'org)
(require 'pdf-annot)

(defgroup org-noter-rehighlight nil
  "Reapply org-noter highlights as pdf-tools session annotations."
  :group 'org
  :prefix "org-noter-rehighlight-")

(defun org-noter-rehighlight--extract-region-from-highlight (highlight-string)
  "Extract REGION from HIGHLIGHT-STRING.

HIGHLIGHT-STRING is expected to be the Org property value from :HIGHLIGHT:,
typically something like:

  \"#s(pdf-highlight 1 (1 (x1 y1 x2 y2 ...)))\"

This function returns the region payload:

  (1 (x1 y1 x2 y2 ...))

which matches the shape returned by `pdf-view-active-region`."
  (let* ((hobj (read highlight-string))
         ;; In vedang/org-noter-pdftools, the region payload is stored in slot 2.
         (region (aref hobj 2)))
    region))

(defun org-noter-rehighlight--collect-regions-in-buffer ()
  "Collect all regions from headings in the current Org buffer that have :HIGHLIGHT:.

Returns a list of REGION objects of the form (PAGE (x1 y1 x2 y2 ...))."
  (let (regions)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward org-heading-regexp nil t)
        (goto-char (match-beginning 0))
        (let ((hstr (org-entry-get (point) "HIGHLIGHT")))
          (when hstr
            (push (org-noter-rehighlight--extract-region-from-highlight hstr)
                  regions)))
        (forward-line 1)))
    (nreverse regions)))

;;;###autoload
(defun org-noter-rehighlight-at-point ()
  "Reapply the current heading's :HIGHLIGHT: as a pdf-tools highlight annotation.

Run this from an org-noter notes buffer (Org mode) with an active org-noter
session. The corresponding PDF buffer must be opened using pdf-tools.

This creates a pdf-tools *session* annotation; it does not modify the PDF file
unless you save it."
  (interactive)
  (let* ((pdf-buf   (org-noter--session-doc-buffer org-noter--session))
         (notes-buf (org-noter--session-notes-buffer org-noter--session))
         (hstr      (org-entry-get (point) "HIGHLIGHT"))
         (region    (org-noter-rehighlight--extract-region-from-highlight hstr))
         (pdfwin    (get-buffer-window pdf-buf t))
         (noteswin  (selected-window)))
    (save-selected-window
      (if pdfwin
          (select-window pdfwin)
        (pop-to-buffer pdf-buf))
      (pdf-annot-add-highlight-markup-annotation region))
    (select-window noteswin)
    (switch-to-buffer notes-buf)))

;;;###autoload
(defun org-noter-rehighlight-buffer-batch ()
  "Reapply all :HIGHLIGHT: regions in this org-noter notes buffer (batch, no flicker).

This scans all headings (any level) in the current Org buffer and re-applies
their stored highlights as pdf-tools session annotations in the associated PDF
buffer. The PDF window is selected only once; redisplay is inhibited during the
loop and triggered once at the end."
  (interactive)
  (let* ((notes-buf (current-buffer))
         (pdf-buf   (org-noter--session-doc-buffer org-noter--session))
         (pdfwin    (or (get-buffer-window pdf-buf t)
                        (progn (pop-to-buffer pdf-buf) (selected-window))))
         (noteswin  (selected-window))
         (regions   (org-noter-rehighlight--collect-regions-in-buffer))
         (count     0))
    (save-selected-window
      (select-window pdfwin)
      (let ((inhibit-redisplay t))
        (dolist (region regions)
          (pdf-annot-add-highlight-markup-annotation region)
          (setq count (1+ count))))
      (when (fboundp 'pdf-view-redisplay)
        (pdf-view-redisplay)))
    (select-window noteswin)
    (switch-to-buffer notes-buf)
    (message "org-noter-rehighlight: reapplied %d highlights (batch)." count)))

(provide 'org-noter-rehighlight)

;;; org-noter-rehighlight.el ends here
