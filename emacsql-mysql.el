;;; emacsql-mysql.el --- back-end for MySQL -*- lexical-binding: t; -*-

;; This is free and unencumbered software released into the public domain.

;; Author: Christopher Wellons <wellons@nullprogram.com>
;; URL: https://github.com/skeeto/emacsql
;; Version: 1.0.0
;; Package-Requires: ((emacs "24.3") (cl-lib "0.3") (emacsql "1.0.2"))

;;; Commentary:

;; This backend uses the standard "mysql" command line program.

;;; Code:

(require 'cl-lib)
(require 'eieio)
(require 'emacsql)

(defvar emacsql-mysql-executable "mysql"
  "Path to the mysql command line executable.")

(defvar emacsql-mysql-sentinel "--------------\n\n--------------\n\n"
  "What MySQL will print when it has completed its output.")

(defvar emacsql-mysql-reserved
  (emacsql-register-reserved
   '(ACCESSIBLE ADD ALL ALTER ANALYZE AND AS ASC ASENSITIVE BEFORE
     BETWEEN BIGINT BINARY BLOB BOTH BY CALL CASCADE CASE CHANGE CHAR
     CHARACTER CHECK COLLATE COLUMN CONDITION CONSTRAINT CONTINUE
     CONVERT CREATE CROSS CURRENT_DATE CURRENT_TIME CURRENT_TIMESTAMP
     CURRENT_USER CURSOR DATABASE DATABASES DAY_HOUR DAY_MICROSECOND
     DAY_MINUTE DAY_SECOND DEC DECIMAL DECLARE DEFAULT DELAYED DELETE
     DESC DESCRIBE DETERMINISTIC DISTINCT DISTINCTROW DIV DOUBLE DROP
     DUAL EACH ELSE ELSEIF ENCLOSED ESCAPED EXISTS EXIT EXPLAIN FALSE
     FETCH FLOAT FLOAT4 FLOAT8 FOR FORCE FOREIGN FROM FULLTEXT GENERAL
     GRANT GROUP HAVING HIGH_PRIORITY HOUR_MICROSECOND HOUR_MINUTE
     HOUR_SECOND IF IGNORE IGNORE_SERVER_IDS IN INDEX INFILE INNER
     INOUT INSENSITIVE INSERT INT INT1 INT2 INT3 INT4 INT8 INTEGER
     INTERVAL INTO IS ITERATE JOIN KEY KEYS KILL LEADING LEAVE LEFT
     LIKE LIMIT LINEAR LINES LOAD LOCALTIME LOCALTIMESTAMP LOCK LONG
     LONGBLOB LONGTEXT LOOP LOW_PRIORITY MASTER_HEARTBEAT_PERIOD
     MASTER_SSL_VERIFY_SERVER_CERT MATCH MAXVALUE MAXVALUE MEDIUMBLOB
     MEDIUMINT MEDIUMTEXT MIDDLEINT MINUTE_MICROSECOND MINUTE_SECOND
     MOD MODIFIES NATURAL NOT NO_WRITE_TO_BINLOG NULL NUMERIC ON
     OPTIMIZE OPTION OPTIONALLY OR ORDER OUT OUTER OUTFILE PRECISION
     PRIMARY PROCEDURE PURGE RANGE READ READS READ_WRITE REAL
     REFERENCES REGEXP RELEASE RENAME REPEAT REPLACE REQUIRE RESIGNAL
     RESIGNAL RESTRICT RETURN REVOKE RIGHT RLIKE SCHEMA SCHEMAS
     SECOND_MICROSECOND SELECT SENSITIVE SEPARATOR SET SHOW SIGNAL
     SIGNAL SLOW SMALLINT SPATIAL SPECIFIC SQL SQL_BIG_RESULT
     SQL_CALC_FOUND_ROWS SQLEXCEPTION SQL_SMALL_RESULT SQLSTATE
     SQLWARNING SSL STARTING STRAIGHT_JOIN TABLE TERMINATED THEN
     TINYBLOB TINYINT TINYTEXT TO TRAILING TRIGGER TRUE UNDO UNION
     UNIQUE UNLOCK UNSIGNED UPDATE USAGE USE USING UTC_DATE UTC_TIME
     UTC_TIMESTAMP VALUES VARBINARY VARCHAR VARCHARACTER VARYING WHEN
     WHERE WHILE WITH WRITE XOR YEAR_MONTH ZEROFILL))
  "List of all of MySQL's reserved words.
http://dev.mysql.com/doc/refman/5.5/en/reserved-words.html")

(defclass emacsql-mysql-connection (emacsql-connection)
  ((dbname :reader emacsql-psql-dbname :initarg :dbname)
   (types :allocation :class
          :reader emacsql-types
          :initform '((integer "BIGINT")
                      (float "DOUBLE")
                      (object "LONGTEXT")
                      (nil "LONGTEXT")))))

(cl-defun emacsql-mysql (database &key user password host port debug)
  "Connect to a MySQL server using the mysql command line program."
  (let* ((mysql (executable-find emacsql-mysql-executable))
         (command (list database "--skip-pager" "-rfBNL" mysql)))
    (when user     (push (format "--user=%s" user) command))
    (when password (push (format "--password=%s" password) command))
    (when host     (push (format "--host=%s" host) command))
    (when port     (push (format "--port=%s" port) command))
    (let* ((process-connection-type t)
           (buffer (generate-new-buffer " *emacsql-mysql*"))
           (command (mapconcat #'shell-quote-argument (nreverse command) " "))
           (process (start-process-shell-command
                     "emacsql-mysql" buffer (concat "stty raw &&" command)))
           (connection (make-instance 'emacsql-mysql-connection
                                      :process process
                                      :dbname database)))
      (setf (process-sentinel process)
            (lambda (proc _) (kill-buffer (process-buffer proc))))
      (when debug (emacsql-enable-debugging connection))
      (emacsql connection
               [:set-session (= sql-mode 'NO_BACKSLASH_ESCAPES\,ANSI_QUOTES)])
      (emacsql connection
               [:set-transaction-isolation-level :serializable])
      (emacsql-register connection))))

(defmethod emacsql-close ((connection emacsql-mysql-connection))
  (let ((process (emacsql-process connection)))
    (when (process-live-p process)
      (process-send-eof process))))

(defmethod emacsql-send-message ((connection emacsql-mysql-connection) message)
  (let ((process (emacsql-process connection)))
    (process-send-string process message)
    (process-send-string process "\\c\\p\n")))

(defmethod emacsql-waiting-p ((connection emacsql-mysql-connection))
  (let ((length (length emacsql-mysql-sentinel)))
    (with-current-buffer (emacsql-buffer connection)
      (and (>= (buffer-size) length)
           (progn (setf (point) (- (point-max) length))
                  (looking-at emacsql-mysql-sentinel))))))

(defmethod emacsql-parse ((connection emacsql-mysql-connection))
  (with-current-buffer (emacsql-buffer connection)
    (let ((standard-input (current-buffer)))
      (setf (point) (point-min))
      (when (looking-at "ERROR")
        (search-forward ": ")
        (signal 'emacsql-error
                (list (buffer-substring (point) (line-end-position)))))
      (cl-loop until (looking-at emacsql-mysql-sentinel)
               collect (read) into row
               when (looking-at "\n")
               collect row into rows
               and do (setf row ())
               and do (forward-char)
               finally (cl-return rows)))))

(provide 'emacsql-mysql)

;;; emacsql-mysql.el ends here
