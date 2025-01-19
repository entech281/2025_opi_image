import cscore as cs
import numpy as np
import cv2
import time
import os, sys

import threading
from queue import Queue

from robotpy_apriltag import AprilTagDetector


def print_camera_properties(camera):
    print("Properties:")
    for prop in camera.enumerateProperties():
        kind = prop.getKind()
        if kind == cs.VideoProperty.Kind.kBoolean:
            print(
                prop.getName(),
                "(bool) value=%s default=%s" % (prop.get(), prop.getDefault()),
            )
        elif kind == cs.VideoProperty.Kind.kInteger:
            print(
                prop.getName(),
                "(int): value=%s min=%s max=%s step=%s default=%s"
                % (
                    prop.get(),
                    prop.getMin(),
                    prop.getMax(),
                    prop.getStep(),
                    prop.getDefault(),
                ),
            )
        elif kind == cs.VideoProperty.Kind.kString:
            print(prop.getName(), "(string):", prop.getString())
        elif kind == cs.VideoProperty.Kind.kEnum:
            print(prop.getName(), "(enum): value=%s" % prop.get())
            for i, choice in enumerate(prop.getChoices()):
                if choice:
                    print("    %s: %s" % (i, choice))


SETTINGS_STREAM_PORT=5800
ANNOTATED_STREAM_PORT=5801
RESOLUTION_WIDTH=640
RESOLUTION_HEIGHT=480
FRAME_RATE=120

class FrameTimer(object):

    def __init__(self,sample_count):
        self.sample_count = sample_count
        self.start_time = time.time()
        self.samples = 0
        self.sps = 0

    def tick(self):
        self.samples += 1
        if self.samples > self.sample_count:
            elapsed = time.time() - self.start_time
            self.sps = self.sample_count / elapsed
            self.start_time = time.time()
            self.samples =0


def main():

    camera = cs.UsbCamera("usbcam", 0)
    camera.getProperty('auto_exposure').set(1)
    camera.getProperty('white_balance_automatic').set(0)
    camera.getProperty('raw_exposure_time_absolute').set(15)
    print_camera_properties(camera)

    camera.setVideoMode(cs.VideoMode.PixelFormat.kMJPEG, RESOLUTION_WIDTH,RESOLUTION_HEIGHT, FRAME_RATE)

    detector = AprilTagDetector()
    detector_config = AprilTagDetector.Config()
    detector_config.numThreads =4
    detector_config.refineEdges = True
    detector_config.quadDecimate = 2  ## 2 vs 1 makes a HUGE difference!!!
    detector_config.quadSigma = 0
    quad_params = AprilTagDetector.QuadThresholdParameters()

    quad_params.maxNumMaxima = 10
    quad_params.criticalAngle = 45 * 3.14159 / 180.0
    quad_params.maxLineFitMSE = 10.0
    quad_params.minWhiteBlackDiff = 5
    quad_params.deglitch = False
    quad_params.minClusterPixels = 5
    quad_params.minWhiteBlackDiff = 5

    detector.setConfig(detector_config)
    detector.setQuadThresholdParameters(quad_params)

    frame_timer = FrameTimer(200)

    detector.addFamily("tag36h11")

    mjpegServer = cs.MjpegServer("httpserver", SETTINGS_STREAM_PORT)
    mjpegServer.setSource(camera)

    print(f"mjpg server listening at http://0.0.0.0:{SETTINGS_STREAM_PORT}")

    cvsink = cs.CvSink("cvsink")
    cvsink.setSource(camera)

    cvSource = cs.CvSource("cvsource", cs.VideoMode.PixelFormat.kMJPEG, RESOLUTION_WIDTH,RESOLUTION_HEIGHT, FRAME_RATE)
    cvMjpegServer = cs.MjpegServer("cvhttpserver", ANNOTATED_STREAM_PORT)
    cvMjpegServer.setSource(cvSource)

    print(f"OpenCV output mjpg server listening at http://0.0.0.0:{ANNOTATED_STREAM_PORT}")

    initial_data = np.zeros(shape=(RESOLUTION_HEIGHT, RESOLUTION_WIDTH, 3), dtype=np.uint8)

    while True:
        frame_timer.tick()
        time, frame = cvsink.grabFrame(initial_data)
        if time == 0:
            print("error:", cvsink.getError())
            continue
        fps = frame_timer.sps

        cv2.putText(frame, f"{fps:.0f} FPS",(20,30),cv2.FONT_HERSHEY_SIMPLEX,1.2,(0,255,0),2, cv2.LINE_AA)
        cv2.putText(frame, f"Default Code", (50, 100),cv2.FONT_HERSHEY_SIMPLEX,1,(0,255,0),2, cv2.LINE_AA)

        gray_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY,3)

        detections = detector.detect(gray_frame)
        for detection in detections:
           tag_id = detection.getId()
           center = detection.getCenter()  # (x, y) coordinates of the center
           corner0 = detection.getCorner(0)
           corner1 = detection.getCorner(1)
           corner2 = detection.getCorner(2)
           corner3 = detection.getCorner(3)

           # Draw the center point and tag ID on the frame
           cv2.circle(frame, (int(center[0]), int(center[1])), 5, (0, 255, 0), -1)
           cv2.putText(frame, f"ID: {tag_id}", (int(center[0]), int(center[1]) - 10),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1, cv2.LINE_AA)

           # Draw the tag's corners on the frame
           def line_between_pnts (pt1, pt2):

               p1 = (int(pt1.x), int(pt1.y))
               p2 = (int(pt2.x), int(pt2.y))
               cv2.line(frame, p1, p2, (255, 0, 0), 2)

           line_between_pnts(detection.getCorner(0), detection.getCorner(1))
           line_between_pnts(detection.getCorner(1), detection.getCorner(2))
           line_between_pnts(detection.getCorner(2), detection.getCorner(3))
           line_between_pnts(detection.getCorner(3), detection.getCorner(0))

           # Print the tag's center coordinates
           #print(f"Detected Tag ID: {tag_id}, Center: {center}")

        cvSource.putFrame(frame)
if __name__ == '__main__':
     main()
