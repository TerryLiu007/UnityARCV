﻿using UnityEngine;
using System;
using System.Collections;
using System.Runtime.InteropServices;
using UnityEngine.XR.iOS;

public class VideoCapture : MonoBehaviour {
	// pixel width
	public int width = 360;
	// pixel height
	public int height = 480;

	// input width
	private int inputWidth;
	private int inputHeight;

	public Renderer renderTarget;

	// Import external library
	[DllImport("__Internal")]
	private static extern IntPtr allocateVideoCapture(int width, int height);

	[DllImport("__Internal")]
	private static extern void releaseVideoCapture(IntPtr capture);

	[DllImport("__Internal")]
	private static extern void updateVideoCapture(IntPtr capture, int width, int height, IntPtr inputImage, IntPtr outputImage);

	[DllImport("__Internal")]
	private static extern void OpenCVPixelData (int enable, IntPtr YPixelBytes);

	// Set up ARKit related parameters
	private UnityARSessionNativeInterface m_Session;
	private bool texturesInitialized;

	// Pointer to device capture
	private IntPtr nativeCapture;

	// Input
	private byte[] textureYBytes;
	private GCHandle textureYHandle;
	private IntPtr textureYInputPtr;

	// Output
	private Texture2D texture;
	private Color32[] pixels;
	private GCHandle pixelsHandle;
	private IntPtr pixelsOutputPtr;

	// Use this for initialization
	void Start () {
		
		#if UNITY_IOS
		UnityARSessionNativeInterface.ARFrameUpdatedEvent += UpdateCamera;
		texturesInitialized = false;

		nativeCapture = allocateVideoCapture(width, height);

		texture = new Texture2D(width, height, TextureFormat.ARGB32, false);
		pixels = texture.GetPixels32();
		pixelsHandle = GCHandle.Alloc(pixels, GCHandleType.Pinned);
		pixelsOutputPtr = pixelsHandle.AddrOfPinnedObject();

		#endif

		renderTarget.material.mainTexture = texture;
	}


	void UpdateCamera(UnityARCamera camera)
	{
		if (!texturesInitialized) {
			InitializeTextures (camera);
		}
		UnityARSessionNativeInterface.ARFrameUpdatedEvent -= UpdateCamera;

	}


	void InitializeTextures(UnityARCamera camera)
	{
		inputWidth = camera.videoParams.yWidth;
		inputHeight = camera.videoParams.yHeight;

		textureYBytes = new byte[inputWidth * inputHeight];
		textureYHandle = GCHandle.Alloc(textureYBytes, GCHandleType.Pinned);
		textureYInputPtr = textureYHandle.AddrOfPinnedObject();

		texturesInitialized = true;
	}


	void Update() {
		
		#if UNITY_IOS

		if (!texturesInitialized)
			return;

		//Resolution currentResolution = Screen.currentResolution;

		SetOpenCVPixelData (true, textureYInputPtr);

		updateVideoCapture(nativeCapture, inputWidth, inputHeight, textureYInputPtr, pixelsOutputPtr);
		texture.SetPixels32(pixels);
		texture.Apply();

		#endif
	
	}


	void OnDestroy () {
		
		#if UNITY_IOS

		textureYHandle.Free();
		pixelsHandle.Free();
		releaseVideoCapture(nativeCapture);

		#endif
	}


	public void SetOpenCVPixelData(bool enable, IntPtr YByteArray)
	{
		#if UNITY_IOS

		int iEnable = enable ? 1 : 0;
		OpenCVPixelData (iEnable, YByteArray);

		#endif
	}
}
