#|
 This file is a part of Qtools
 (c) 2014 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.qtools)
(named-readtables:in-readtable :qt)

(defvar *method*)
(defvar *method-declarations* (make-hash-table :test 'eql))

(defun method-declaration (name)
  (gethash name *method-declarations*))

(defun (setf method-declaration) (function name)
  (setf (gethash name *method-declarations*) function))

(defun remove-method-declaration (name)
  (remhash name *method-declarations*))

(defmacro define-method-declaration (name args &body body)
  `(setf (method-declaration ',name)
         #'(lambda ,args ,@body)))

(defmacro cl+qt:defmethod (&whole whole name &rest args)
  (declare (ignore args))
  ;; Split multi-specifier declarations into singulars.
  (let ((all-declarations (loop for form in (form-fiddle:lambda-declarations whole)
                                append (loop for specifier in (rest form)
                                             collect `(declare ,specifier))))
        (declaration-forms)
        (known-declarations))
    ;; Rebuild method with new declarations
    (form-fiddle:with-destructured-lambda-form (:qualifiers qualifiers :lambda-list args :docstring docs :forms forms) whole
      (let* ((name (ensure-cl-function-name name))
             (*method* `(cl:defmethod ,name ,@qualifiers ,args
                         ,@(when docs (list docs))
                         ,@all-declarations
                         ,@forms)))
        ;; Process declarations
        (loop for declaration in all-declarations
              for (name . args) = (second declaration)
              for declaration-function = (method-declaration name)
              do (when declaration-function
                   (push (apply declaration-function args) declaration-forms)
                   (push declaration known-declarations)))
        ;; Remove the known declarations from the method body
        (loop for declaration in known-declarations
              do (setf *method* (delete declaration *method*)))
        `(progn
           (eval-when (:compile-toplevel :load-toplevel :execute)
             ,@declaration-forms)
           ,*method*)))))

(defmacro with-widget-class ((variable &optional (method '*method*)) &body body)
  `(let ((,variable (second (first (form-fiddle:lambda-lambda-list ,method)))))
     (assert (not (null ,variable)) () "Method must have a primary specializer.")
     (assert (not (listp ,variable)) () "Primary specializer cannot be an EQL-specializer.")
     (locally
         ,@body)))

(defun slot-initializer-symbol (slot)
  (intern (format NIL "%~a-CONNECTORS" slot)))

(define-method-declaration slot (name args)
  (form-fiddle:with-destructured-lambda-form (:name method :declarations declarations) *method*
    (let ((slot (qtools:specified-type-method-name name args))
          (connectors (remove 'connected declarations :test-not #'eql :key #'caadr))
          (connectors-initializer (slot-initializer-symbol name)))
      (with-widget-class (widget-class)
        (dolist (connector connectors)
          (setf *method* (delete connector *method*)))
        `(progn
           (unless (widget-class-option-p ',widget-class :slots '(,slot ,method) :key #'identity)
             (set-widget-class-option ',widget-class :slots '(,slot ,method)))
           ,@(when connectors
               `((define-initializer (,widget-class ,connectors-initializer 9)
                   ,@(loop for connector in connectors
                           for (source source-args) = (rest (second connector))
                           collect `(connect! ,source ,source-args ,widget-class (,name ,@args)))))))))))

(define-method-declaration override (&optional name)
  (let* ((lambda-name (form-fiddle:lambda-name *method*))
         (slot (qtools:to-method-name (or name lambda-name))))
    (with-widget-class (widget-class)
      `(unless (widget-class-option-p ',widget-class :override '(,slot ,lambda-name) :key #'identity)
         (set-widget-class-option ',widget-class :override '(,slot ,lambda-name))))))

(define-method-declaration initializer (&optional (priority 0))
  (let ((method (form-fiddle:lambda-name *method*)))
    (with-widget-class (widget-class)
      `(unless (widget-class-option-p ',widget-class :initializers '(,method ,priority ,method) :key #'identity)
         (set-widget-class-option ',widget-class :initializers '(,method ,priority ,method))))))

(define-method-declaration finalizer (&optional (priority 0))
  (let ((method (form-fiddle:lambda-name *method*)))
    (with-widget-class (widget-class)
      `(unless (widget-class-option-p ',widget-class :finalizers '(,method ,priority ,method) :key #'identity)
         (set-widget-class-option ',widget-class :finalizers '(,method ,priority ,method))))))
