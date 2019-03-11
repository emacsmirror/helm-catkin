;;; catkin.el --- Package for compile ROS workspaces with catkin-tools  -*- lexical-binding: t; -*-

;; Copyright (C) 2019  Thore Goll

;; Author:  gollth
;; Keywords: tools, ROS

;;; Code:

(require 'helm)
(require 'xterm-color)

(defconst WS "EMACS_CATKIN_WS")

(defun catkin-util-format-list (list sep)
  (mapconcat 'identity list sep)
  )

(defun catkin-util-command-to-list (command &optional separator)
  "Returns each part of the stdout of `command' as elements of a list.
   If `separator' is nil, the newline character is used to split stdout."
  (let ((sep (if separator separator "\n")))
    (with-temp-buffer
      (call-process-shell-command command nil t)
      (split-string (buffer-string) sep t)
      )
    )
  )


(defun catkin-set-ws (&optional ws)
  (if ws
      (setenv WS ws)
    (loop for path in (split-string (getenv "CMAKE_PREFIX_PATH") ":")
          if (file-exists-p (format "%s/.catkin" path))
          do (setenv WS path)
          and do (message (format "Catkin: Setting workspace to %s" path))
          and do (return)
          finally do (error "Could not find any catkin workspace within $CMAKE_PREFIX_PATH =(")
          )
    )
  )

(defun catkin-cd (cmd)
  (let ((ws (getenv WS)))
    (if cmd (format "cd %s && %s" ws cmd))
    )
  )

(defun catkin-init ()
  "(Re-)Initializes a catkin workspace at path"
  (let ((ws (getenv WS)))
    (unless (file-exists-p ws)
      (unless (y-or-n-p (format "Path %s does not exist. Create?" ws))
        (error "Cannot initialize workspace `%s' since it doesn't exist" ws)
        )
      (make-directory (format "%s/src" ws) t)  ; also create parent directiories
      (call-process-shell-command (format "catkin init --workspace %s" ws))
      )
    )
  )

(defun catkin-source (command)
  "Prepends a source $EMACS_CATKINB_WS/devel/setup.bash before `command' if such a file exists."
  (let* ((ws (getenv WS))
         (setup-file (format "%s/devel/setup.bash" ws)))
    (if (file-exists-p setup-file)
        (format "source %s && %s" setup-file command)
      command
      )
    )
  )

(defun catkin-config-print ()
  "Prints the catkin config of $EMACS_CATKIN_WS to a new buffer called *catkin-config*"
  (switch-to-buffer-other-window "*catkin-config*")
  (erase-buffer)
  ; Pipe stderr to null to supress "could not determine width" warning
  (call-process-shell-command (format "catkin --force-color config --workspace %s 2> /dev/null" (getenv WS)) nil t)
  (xterm-color-colorize-buffer)
  (other-window 1)
  )

(defun catkin-config-args (operation &optional args)
  (let ((arg-string (catkin-util-format-list args " ")))
    (call-process-shell-command
       (format "catkin config --workspace %s %s %s" (getenv WS) operation arg-string)
     )
   )
  )
(defun catkin-config-args-find (filter)
  (catkin-util-command-to-list
   ;; due to https://github.com/catkin/catkin_tools/issues/519 catkin config without args
   ;; clears make-args, thats why we use the -a switch to prevent that until this gets fixed
   ;; Supress stderr for "Could not determine width of terminal" warnings
   (format "catkin --no-color config -a --workspace %s 2> /dev/null | sed -n 's/%s//p'"
           (getenv WS)
           filter
           )
   " "
   )
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                  CMAKE Args                                ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun catkin-config-cmake-args ()
  "Returns a list of all currenty set cmake args for the workspace
   at $EMACS_CATKIN_WS"
  (catkin-config-args-find "Additional CMake Args:\s*")
  )

(defalias 'catkin-config-cmake-args-clear (apply-partially 'catkin-config-args "--no-cmake-args")
  "Removes all cmake args for the current workspace at $EMACS_CATKIN_WS"
  )
(defalias 'catkin-config-cmake-args-set (apply-partially 'catkin-config-args "--cmake-args")
  "Sets a list of cmake args for the current workspace at $EMACS_CATKIN_WS.
   Passing an empty list to `args' will clear all currently set args."
  )

(defalias 'catkin-config-cmake-args-add (apply-partially 'catkin-config-args "--append-args --cmake-args")
  "Adds a list of cmake args to the existing set of cmake args for the
   current workspace at $EMACS_CATKIN_WS."
  )
(defalias 'catkin-config-cmake-args-remove (apply-partially 'catkin-config-args "--remove-args --cmake-args")
  "Removes a list of cmake args from the existing set of cmake args for
   the current workspace at $EMACS_CATKIN_WS. Args which are currently
   not set and are requested to be removed don't provoce an error and
   are just ignored."
  )
(defun catkin-config-cmake-change (arg)
  "Prompts the user to enter a new value for a CMake arg. The prompt in the
   minibuffer is autofilled with `arg' and the new entered value will be returned."
  (interactive)
  (let ((new-arg (helm-read-string "Adjust value for CMake Arg: " arg)))
    (catkin-config-cmake-args-remove (list arg))
    (catkin-config-cmake-args-add (list new-arg))
    )
  )

(defun catkin-config-cmake-new (&optional _)
  "Prompts the user to enter a new CMake arg which will be returned."
  (interactive)
  (catkin-config-cmake-args-add (list (helm-read-string "New CMake Arg: ")))
  )

(defvar catkin-config-cmake-sources
  (helm-build-sync-source "CMake"
    :candidates 'catkin-config-cmake-args
    :action '(
              ("Change" . catkin-config-cmake-change)
              ("Add" . catkin-config-cmake-new)
              ("Clear" . (lambda (_) (catkin-config-cmake-args-remove (helm-marked-candidates))))
              )
    )
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                   MAKE Args                                ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun catkin-config-make-args ()
  "Returns a list of all currenty set make args for the workspace
   at $EMACS_CATKIN_WS"
  (catkin-config-args-find "Additional Make Args:\s*")
  )

(defalias 'catkin-config-make-args-clear (apply-partially 'catkin-config-args "--no-make-args")
  "Removes all make args for the current workspace at $EMACS_CATKIN_WS"
  )
(defalias 'catkin-config-make-args-set (apply-partially 'catkin-config-args "--make-args")
  "Sets a list of make args for the current workspace at $EMACS_CATKIN_WS.
   Passing an empty list to `args' will clear all currently set args."
  )

(defalias 'catkin-config-make-args-add (apply-partially 'catkin-config-args "--append-args --make-args")
  "Adds a list of make args to the existing set of make args for the
   current workspace at $EMACS_CATKIN_WS."
  )
(defalias 'catkin-config-make-args-remove (apply-partially 'catkin-config-args "--remove-args --make-args")
  "Removes a list of make args from the existing set of make args for
   the current workspace at $EMACS_CATKIN_WS. Args which are currently
   not set and are requested to be removed don't provoce an error and
   are just ignored."
  )
(defun catkin-config-make-change (arg)
  "Prompts the user to enter a new value for a Make arg. The prompt in the
   minibuffer is autofilled with `arg' and the new entered value will be returned."
  (interactive)
  (let ((new-arg (helm-read-string "Adjust value for Make Arg: " arg)))
    (catkin-config-make-args-remove (list arg))
    (catkin-config-make-args-add (list new-arg))
    )
  )

(defun catkin-config-make-new (&optional _)
  "Prompts the user to enter a new Make arg which will be returned."
  (interactive)
  (catkin-config-make-args-add (list (helm-read-string "New Make Arg: ")))
  )

(defvar catkin-config-make-sources
  (helm-build-sync-source "Make"
    :candidates 'catkin-config-make-args
    :action '(
              ("Change" . catkin-config-make-change)
              ("Add" . catkin-config-make-new)
              ("Clear" . (lambda (_) (catkin-config-make-args-remove (helm-marked-candidates))))
              )
    )
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                   CATKIN-MAKE Args                                ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun catkin-config-catkin-make-args ()
  "Returns a list of all currenty set catkin-make args for the workspace
   at $EMACS_CATKIN_WS"
  (catkin-config-args-find "Additional catkin Make Args:\s*")
  )

(defalias 'catkin-config-catkin-make-args-clear (apply-partially 'catkin-config-args "--no-catkin-make-args")
  "Removes all catkin-make args for the current workspace at $EMACS_CATKIN_WS"
  )
(defalias 'catkin-config-catkin-make-args-set (apply-partially 'catkin-config-args "--catkin-make-args")
  "Sets a list of catkin-make args for the current workspace at $EMACS_CATKIN_WS.
   Passing an empty list to `args' will clear all currently set args."
  )

(defalias 'catkin-config-catkin-make-args-add (apply-partially 'catkin-config-args "--append-args --catkin-make-args")
  "Adds a list of catkin-make args to the existing set of catkin-make args for the
   current workspace at $EMACS_CATKIN_WS."
  )
(defalias 'catkin-config-catkin-make-args-remove (apply-partially 'catkin-config-args "--remove-args --catkin-make-args")
  "Removes a list of catkin-make args from the existing set of catkin-make args for
   the current workspace at $EMACS_CATKIN_WS. Args which are currently
   not set and are requested to be removed don't provoce an error and
   are just ignored."
  )
(defun catkin-config-catkin-make-change (arg)
  "Prompts the user to enter a new value for a Catkin-Make arg. The prompt in the
   minibuffer is autofilled with `arg' and the new entered value will be returned."
  (interactive)
  (let ((new-arg (helm-read-string "Adjust value for Catkin-Make Arg: " arg)))
    (catkin-config-catkin-make-args-remove (list arg))
    (catkin-config-catkin-make-args-add (list new-arg))
    )
  )

(defun catkin-config-catkin-make-new (&optional _)
  "Prompts the user to enter a new Catkin-Make arg which will be returned."
  (interactive)
  (catkin-config-catkin-make-args-add (list (helm-read-string "New Catkin-Make Arg: ")))
  )

(defvar catkin-config-catkin-make-sources
  (helm-build-sync-source "Catkin-Make"
    :candidates 'catkin-config-catkin-make-args
    :action '(
              ("Change" . catkin-config-catkin-make-change)
              ("Add" . catkin-config-catkin-make-new)
              ("Clear" . (lambda (_) (catkin-config-catkin-make-args-remove (helm-marked-candidates))))
              )
    )
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                   Whitelist/Blacklist                      ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun catkin-config-whitelist ()
  "Returns a list of all currenty whitelisted packages for the workspace
   at $EMACS_CATKIN_WS"
  (catkin-config-args-find "Whitelisted Packages:\s*")
  )
(defalias 'catkin-config-whitelist-add (apply-partially 'catkin-config-args "--append-args --whitelist")
  "Marks a list of packages to be whitelisted for the current workspace at $EMACS_CATKIN_WS."
  )
(defalias 'catkin-config-whitelist-remove (apply-partially 'catkin-config-args "--remove-args --whitelist")
  "Removes a list of whitelisted packages from the existing whitelist for
   the current workspace at $EMACS_CATKIN_WS. Packages which are currently
   not whitelisted and are requested to be removed don't provoce an error and
   are just ignored."
  )
(defvar catkin-config-whitelist-sources
  (helm-build-sync-source "Whitelist"
    :candidates 'catkin-config-whitelist
    :action '(("Un-Whitelist" . (lambda (_) (catkin-config-whitelist-remove (helm-marked-candidates)))))
    )
  )

(defun catkin-config-blacklist ()
  "Returns a list of all currenty blacklisted packages for the workspace
   at $EMACS_CATKIN_WS"
  (catkin-config-args-find "Blacklisted Packages:\s*")
  )
(defalias 'catkin-config-blacklist-add (apply-partially 'catkin-config-args "--append-args --blacklist")
  "Marks a list of packages to be blacklisted for the current workspace at $EMACS_CATKIN_WS."
  )
(defalias 'catkin-config-blacklist-remove (apply-partially 'catkin-config-args "--remove-args --blacklist")
  "Removes a list of blacklisted packages from the existing blacklist for
   the current workspace at $EMACS_CATKIN_WS. Packages which are currently
   not blacklisted and are requested to be removed don't provoce an error and
   are just ignored."
  )
(defvar catkin-config-blacklist-sources
  (helm-build-sync-source "Blacklist"
    :candidates 'catkin-config-blacklist
    :action '(("Un-Blacklist" . (lambda (_) (catkin-config-blacklist-remove (helm-marked-candidates)))))
    )
  )
(defvar catkin-config-packages-sources
  (helm-build-sync-source "Packages"
    :candidates 'catkin-list-candidates
    :action '(
              ("Blacklist" . (lambda (_) (catkin-config-blacklist-add (helm-marked-candidates))))
              ("Whitelist" . (lambda (_) (catkin-config-whitelist-add (helm-marked-candidates))))
              )
    )
  )

(defun catkin-config ()
  (interactive)
  (helm :buffer "*helm catkin config*"
        :sources '(catkin-config-cmake-sources
                   catkin-config-make-sources
                   catkin-config-catkin-make-sources
                   catkin-config-whitelist-sources
                   catkin-config-blacklist-sources
                   catkin-config-packages-sources
                   )
        )
  )

(defun catkin-build-finished (process signal)
  "This gets called, once the catkin build command finishes. It marks the buffer
   as read-only and asks to close the window"
  (when (memq (process-status process) '(exit signal))
    (message "Catkin build done!")
    (other-window 1)     ; select the first "other" window, i.e. the build window
    (evil-normal-state)  ; leave insert mode
    (read-only-mode)     ; mark as not-editable
    (when (y-or-n-p "Catkin build done. Close window?")
      (delete-window)
      )
    )
  )


(defun catkin-build-package (&optional pkgs)
  "Build the catkin workspace at $EMACS_CATKIN_WS after sourcing it's ws.
   If `pkgs' is non-nil, only these packages are built, otherwise all packages in the ws are build"
  (let* ((packages (catkin-util-format-list pkgs " "))
         (build-command (catkin-source (format "catkin build --workspace %s %s" (getenv WS) packages)))
         (buffer (get-buffer-create "*Catkin Build*"))
         (process (progn
                    (async-shell-command build-command buffer)
                    (get-buffer-process buffer)
                    ))
         )
    (if (process-live-p process)
        (set-process-sentinel process #'catkin-build-finished)
      (error "Could not attach process sentinel to \"catkin build\" since no such process is running")
      )
    )
  )

(defun catkin-list ()
  "Returns a list of all packages in the workspace at $EMACS_CATKIN_WS"
  (catkin-util-command-to-list
   (format "catkin list --workspace %s --unformatted --quiet" (getenv WS)))
  )

(defun catkin-list-candidates (&optional include-all-option)
  "Assembes the list of packages in the current workspace.
   If the `include-all-option' parameter is non-nil another
   item with the value \"[*]\" is prepended to the list."
  (if include-all-option
      (cons "[*]" (catkin-list))
    ; else
    (catkin-list)
    )
  )

(defun catkin-get-absolute-path-of-pkg (pkg)
  "Returns the absolute path of `pkg' by calling \"rospack find ...\""
  (shell-command-to-string (catkin-source (format "printf $(rospack find %s)" pkg)))
  )

(defun catkin-open-file-in (pkg file)
  "Opens the file at \"$(rospack find pkg)/file\". `file' can be a
   relative path to `pkg'."
  (interactive)
  (find-file (format "%s/%s" (catkin-get-absolute-path-of-pkg pkg) file))
  )

(defun catkin-open-pkg-cmakelist (pkgs)
  "Opens the 'CMakeLists.txt' file for each of the package names within `pkgs'"
  (loop for pkg in pkgs
        do (catkin-open-file-in pkg "CMakeLists.txt")
        )
  )

(defun catkin-open-pkg-package (pkgs)
  "Opens the 'package.xml' file for each of the package names within `pkgs'"
  (loop for pkg in pkgs
        do (catkin-open-file-in pkg "package.xml")
        )
  )

(defun catkin-open-pkg-dired (pkg)
  "Opens the absolute path of `pkg' in dired."
  (interactive)
  (dired (catkin-get-absolute-path-of-pkg pkg))
  )

(defun catkin-build ()
  "Prompts the user via a helm dialog to select one or more
   packages to build in the current workspace. C-SPC will enable
   multiple selections while M-a selects all packages."
  (interactive)
  (helm :buffer "*helm catkin list*"
        :sources (helm-build-sync-source "Packages"
                   :candidates (catkin-list-candidates)
                   :fuzzy-match t
                   :action '(("Build" . (lambda (c) (catkin-build-package (helm-marked-candidates))))
                             ("Open Folder" . catkin-open-pkg-dired)
                             ("Open CMakeLists.txt" . (lambda (c) (catkin-open-pkg-cmakelist (helm-marked-candidates))))
                             ("Open package.xml" . (lambda (c) (catkin-open-pkg-package (helm-marked-candidates))))
                             )
                   )
        )
  )


;; Tests
(catkin-set-ws "~/ros/util")
(catkin-config-cmake-args-clear)
(catkin-config-cmake-args-set '("-DCMAKE_BUILD_TYPE=Release"))
(catkin-config-cmake-args-add '("-DCHELLO" "-DCFOO=bar"))
(catkin-config-cmake-args-remove '("-DCHELLO" "BLUB"))
(catkin-config-make-args-set '("-j4"))
(catkin-config)

;;; catkin.el ends here
