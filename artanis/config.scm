;;  -*-  indent-tabs-mode:nil; coding: utf-8 -*-
;;  Copyright (C) 2013,2014
;;      "Mu Lei" known as "NalaGinrut" <NalaGinrut@gmail.com>
;;  Artanis is free software: you can redistribute it and/or modify
;;  it under the terms of the GNU General Public License as published by
;;  the Free Software Foundation, either version 3 of the License, or
;;  (at your option) any later version.

;;  Artanis is distributed in the hope that it will be useful,
;;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;  GNU General Public License for more details.

;;  You should have received a copy of the GNU General Public License
;;  along with this program.  If not, see <http://www.gnu.org/licenses/>.

(define-module (artanis config)
  #:use-module (artanis version)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 match)
  #:export (init-config get-conf))

(define server-info artanis-version)
(define *default-conf-file* "/etc/artanis/default.conf")

(define *conf-hash-table* (make-hash-table))
(define (conf-set! k v)
  (hash-set! *conf-hash-table* k v))

(define-syntax-rule (->bool x)
  (case (string->symbol (string-downcase x))
    ((true on yes enable) #t)
    ((fasle off no disable) #f)
    (else (error "Invalid boolean item!" x))))

(define-syntax-rule (->list x)
  (map (lambda (e)
         (string->symbol (string-trim-both e)))
       (string-split x #\,)))

(define-syntax-rule (->none/str x)
  (case (string->symbol (string-downcase x))
    ((none null #{}#) "")
    (else x)))

(define-syntax-rule (->integer x)
  (let ((i (string->number x)))
    (if (>= i 0)
        i
        (error "Invalid integer!" x))))

(define (parse-namespace-db item)
  (match item
    (('dbd dbd) (conf-set! '(db dbd) dbd))
    (('port port) (conf-set! '(db port) (->integer port)))
    (('addr addr) (conf-set! '(db addr) addr))
    (('name name) (conf-set! '(db name) name))
    (('socket sock) (conf-set '(db sock) sock))
    (('username username) (conf-set! '(db username) username))
    (('passwd passwd) (conf-set! '(db passwd) passwd))
    (('pool 'size size) (conf-set! '(db pool size) (->integer size)))
    (else (error parse-namespace-db "Config: Invalid item" item))))

(define (parse-namespace-server item)
  (match item
    (('info info) (conf-set! '(server info) (->none/str info)))
    (('nginx nginx) (conf-set! '(server nginx) (->bool nginx)))
    (('charset charset) (conf-set! '(server charset) charset))
    (('workers workers) (conf-set! '(server workers) (->integer workers)))
    (else (error parse-namespace-server "Config: Invalid item" item))))

(define (parse-namespace-host item)
  (match item
    (('addr addr) (conf-set! '(host addr) addr))
    (('port port) (conf-set! '(host port) (->integer port)))
    (else (error parse-namespace-host "Config: Invalid item" item))))

(define (parse-namespace-error item)
  (match item
    (('path path) (conf-set! '(error path) path))
    (else (error parse-namespace-error "Config: Invalid item" item))))

(define (parse-namespace-session item)
  (match item
    (('path path) (conf-set! '(session path) path))
    (else (error parse-namespace-session "Config: Invalid item" item))))

(define (parse-namespace-upload item)
  (match item
    (('type types) (conf-set! '(upload types) (->list types)))
    (('path path) (conf-set! '(upload path) path))
    (else (error parse-namespace-upload "Config: Invalid item" item))))

(define (parse-namespace-mail item)
  (match item
    (('sender sender) (conf-set! '(mail sender) sender))
    (else (error parse-namespace-mail "Config: Invalid item" item))))

(define (parse-config-item item)
  (match item
    (('db rest ...) (parse-namespace-db rest))
    (('server rest ...) (parse-namespace-server rest))
    (('host rest ...) (parse-namespace-host rest))
    (('error rest ...) (parse-namespace-error rest))
    (('session rest ...) (parse-namespace-session rest))
    (('upload rest ...) (parse-namespace-upload rest))
    (('mail rest ...) (parse-namespace-mail rest))
    (() #t) ; skip
    (else (error parse-config-item "Unsupported config namespace!" item))))

(define (parse-line line)
  (call-with-input-string 
   line
   (lambda (port)
     (let lp((next (read-char port)) (key? #t) (word '()) (ret '()))
       (cond
        ((or (eof-object? next)
             (char=? next #\#)) ; skip comment 
         (reverse (cons (list->string (reverse word)) ret)))
        ((char-set-contains? char-set:whitespace next)
         ;; skip all whitespaces
         (lp (read-char port) key? word ret))
        ((and key? (char=? next #\.))
         ;; a namespace end
         (lp (read-char port) key? '() (cons (list->symbol (reverse word)) ret)))
        ((and key? (char=? next #\=))
         ;; value start
         (lp (read-char port) #f '() (cons (list->symbol (reverse word)) ret)))
        ((not key?)
         ;; store chars of value
         (lp (read-char port) key? (cons next word) ret))
        (else
         ;; store chars of key
         (lp (read-char port) key? (cons next word) ret)))))))

(define (init-inner-database-item)
  (define dbd (get-conf '(db dbd)))
  (define port (get-conf '(db port)))
  (define addr (get-conf '(db addr)))
  (define sock (get-conf '(db sock)))
  (define name (get-conf '(db name)))
  (define username (get-conf '(db username)))
  (define passwd (get-conf '(db passwd)))

  (cond
   ((or (and port addr sock)
        (and port sock)
        (and addr sock))
    (error init-inner-database-item "Conf: either addr:port or sock mode!"))
   ((eq? dbd 'sqlite3) ; sqlite3 needs only dbname
    (conf-set! 'databse `(sqlite3 ,username ,passwd ,name)))
   ((and addr port) ; addr:port mode
    (conf-set! 'database `(,dbd ,username ,passwd ,name (socketfile ,sock))))
   ((and (eq? dbd 'mysql) sock) ; mysql has socket file mode
    (conf-set! 'database `(mysql ,username ,passwd ,name (port ,addr ,port))))
   (else (error init-inner-database-item "Fatal: Invalid database config"))))

(define (init-inner-config-items)
  (init-inner-database-item))

(define (init-config conf-file)
  (define fp (open-input-file 
              (cond
               ((file-exists? conf-file) conf-file)
               ((file-exists? *default-conf-file*) *default-conf-file*)
               (else 
                (error init-config 
                       "Fatal error! You need to reinstall Artanis!")))))
  (let lp((line (read-line fp)))
    (cond
     ((eof-object? line) #t)
     ((parse-line line) 
      => (lambda (item)
           (parse-config-item item)
           (lp (read-line fp))))
     (else (error init-config "Invalid line" line))))
  (init-inner-config-items))